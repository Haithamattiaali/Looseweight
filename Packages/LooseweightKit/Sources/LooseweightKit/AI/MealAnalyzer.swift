import Foundation

/// Crops the original full-resolution photo for the model (the app implements this with ImageIO).
public protocol PhotoZooming: Sendable {
    /// JPEG of a region given in image 1 pixels, resized for the model, or nil when unavailable.
    func zoom(x: Double, y: Double, width: Double, height: Double) async -> Data?
}

/// On-device geometry for the measure tool.
public struct MeasurementContext: Sendable {
    public var measurer: SceneMeasurer
    public var regions: [OnDeviceRegion]

    public init(measurer: SceneMeasurer, regions: [OnDeviceRegion]) {
        self.measurer = measurer
        self.regions = regions
    }
}

public enum AnalysisEffort: String, Codable, CaseIterable, Sendable {
    case high
    case medium

    public var title: String {
        switch self {
        case .high: "Precise"
        case .medium: "Fast"
        }
    }
}

public struct AnalysisRequest: Sendable {
    public var photoJPEG: Data
    public var overlayJPEG: Data?
    public var insights: CaptureInsights
    public var measurement: MeasurementContext?
    public var zoomer: PhotoZooming?
    /// Foods the model may reference by id besides the table (barcode products, the user's own foods).
    public var extraFoods: [FoodRecord]
    public var effort: AnalysisEffort

    public init(photoJPEG: Data, overlayJPEG: Data? = nil, insights: CaptureInsights, measurement: MeasurementContext? = nil,
                zoomer: PhotoZooming? = nil, extraFoods: [FoodRecord] = [], effort: AnalysisEffort = .high) {
        self.photoJPEG = photoJPEG
        self.overlayJPEG = overlayJPEG
        self.insights = insights
        self.measurement = measurement
        self.zoomer = zoomer
        self.extraFoods = extraFoods
        self.effort = effort
    }
}

public enum AnalysisStage: Sendable, Equatable {
    case thinking(turn: Int)
    case searching(String)
    case measuring(Int)
    case zooming
    case checking
}

public struct AnalysisOutcome: Sendable {
    public var estimate: MealEstimate
    public var analysis: AIMealAnalysis
    public var usage: TokenUsage
    public var turns: Int
    public var modelID: String
    public var toolCalls: [String]
}

/// Picks the model once per day: newest Opus that takes images and structured output, unless overridden.
public actor ModelSelector {
    private var cached: (id: String, fetched: Date)?
    private let maxAge: TimeInterval

    public init(maxAge: TimeInterval = 86_400) {
        self.maxAge = maxAge
    }

    public func modelID(client: ClaudeClient, override: String? = nil, now: Date = Date()) async throws -> String {
        if let override, !override.trimmingCharacters(in: .whitespaces).isEmpty { return override }
        if let cached, now.timeIntervalSince(cached.fetched) < maxAge { return cached.id }
        guard let best = ModelResolver.pickBest(from: try await client.listModels()) else { throw ClaudeError.noModelAvailable }
        cached = (best.id, now)
        return best.id
    }
}

public struct MealAnalyzer: Sendable {
    public static let fallbackBeta = "server-side-fallback-2026-07-01"
    public let client: ClaudeClient
    public let database: FoodDatabase
    public var maxTurns = 8
    public var maxTokens = 16_000

    public init(client: ClaudeClient, database: FoodDatabase) {
        self.client = client
        self.database = database
    }

    public func analyze(
        _ request: AnalysisRequest,
        model: String,
        progress: @escaping @Sendable (AnalysisStage) -> Void = { _ in }
    ) async throws -> AnalysisOutcome {
        var tools = [AnalysisPrompt.searchTool]
        if request.measurement != nil { tools.append(AnalysisPrompt.measureTool) }
        if request.zoomer != nil { tools.append(AnalysisPrompt.zoomTool) }

        var messages: [JSONValue] = [AnalysisPrompt.userMessage(photoJPEG: request.photoJPEG, overlayJPEG: request.overlayJPEG, insights: request.insights)]
        var usage = TokenUsage()
        var useFallbacks = true
        var useSystemBreakpoint = true
        var toolCalls: [String] = []
        var turn = 0

        while turn < maxTurns {
            turn += 1
            progress(.thinking(turn: turn))
            let body = Self.body(model: model, maxTokens: maxTokens, tools: tools, messages: messages, effort: request.effort,
                                 fallbacks: useFallbacks, systemBreakpoint: useSystemBreakpoint)
            let response: MessagesResponse
            do {
                response = try await client.createMessage(body: body, betas: useFallbacks ? [Self.fallbackBeta] : [])
            } catch let ClaudeError.http(status, _, message) where status == 400 {
                // Optional features are dropped once if an endpoint or model rejects them, then the turn is retried.
                let lowered = message.lowercased()
                if useFallbacks, lowered.contains("fallback") || lowered.contains("anthropic-beta") {
                    useFallbacks = false
                    turn -= 1
                    continue
                }
                if useSystemBreakpoint, lowered.contains("cache_control") {
                    useSystemBreakpoint = false
                    turn -= 1
                    continue
                }
                throw ClaudeError.http(status: status, type: "invalid_request_error", message: message)
            }
            usage = usage + response.usage

            switch response.stopReason {
            case "refusal":
                throw ClaudeError.refused(category: response.refusalCategory)
            case "max_tokens":
                throw ClaudeError.truncated
            case "pause_turn":
                messages.append(.obj(["role": .string("assistant"), "content": .raw(response.rawContent)]))
            case "tool_use":
                guard !response.toolUses.isEmpty else { throw ClaudeError.invalidResponse("tool_use without tool calls") }
                messages.append(.obj(["role": .string("assistant"), "content": .raw(response.rawContent)]))
                var results: [JSONValue] = []
                for call in response.toolUses {
                    toolCalls.append(call.name)
                    results.append(await runTool(call, request: request, progress: progress))
                }
                messages.append(.obj(["role": .string("user"), "content": .array(results)]))
            default:
                progress(.checking)
                let analysis = try AIMealAnalysis.decode(from: response.text)
                let estimate = NutritionResolver.resolve(
                    analysis,
                    database: database,
                    extraFoods: request.extraFoods + request.insights.barcodes.compactMap(\.product),
                    modelID: response.model.isEmpty ? model : response.model,
                    usedDepth: request.measurement?.measurer.heightField != nil
                )
                return AnalysisOutcome(estimate: estimate, analysis: analysis, usage: usage, turns: turn,
                                       modelID: response.model.isEmpty ? model : response.model, toolCalls: toolCalls)
            }
        }
        throw ClaudeError.invalidResponse("the analysis did not finish within \(maxTurns) turns")
    }

    static func body(model: String, maxTokens: Int, tools: [JSONValue], messages: [JSONValue], effort: AnalysisEffort,
                     fallbacks: Bool, systemBreakpoint: Bool) -> Data {
        var systemBlock: [JSONValue.Field] = [.init("type", .string("text")), .init("text", .string(AnalysisPrompt.system))]
        if systemBreakpoint { systemBlock.append(.init("cache_control", .obj(["type": .string("ephemeral")]))) }
        var fields: [JSONValue.Field] = [
            .init("model", .string(model)),
            .init("max_tokens", .number(Double(maxTokens))),
            .init("system", .array([.object(systemBlock)])),
            .init("tools", .array(tools)),
            .init("tool_choice", .obj(["type": .string("auto")])),
            .init("thinking", .obj(["type": .string("adaptive")])),
            .init("output_config", .obj([
                "effort": .string(effort.rawValue),
                "format": .obj(["type": .string("json_schema"), "schema": AnalysisPrompt.outputSchema]),
            ])),
            .init("messages", .array(messages)),
            .init("cache_control", .obj(["type": .string("ephemeral")])),
        ]
        if fallbacks { fields.append(.init("fallbacks", .string("default"))) }
        return JSONValue.object(fields).serialized()
    }

    // MARK: Tools

    private func runTool(_ call: (id: String, name: String, input: JSONValue), request: AnalysisRequest,
                         progress: @escaping @Sendable (AnalysisStage) -> Void) async -> JSONValue {
        func result(_ content: JSONValue, isError: Bool = false) -> JSONValue {
            var fields: [JSONValue.Field] = [.init("type", .string("tool_result")), .init("tool_use_id", .string(call.id)), .init("content", content)]
            if isError { fields.append(.init("is_error", .bool(true))) }
            return .object(fields)
        }
        switch call.name {
        case "search_foods":
            guard let query = call.input["query"]?.stringValue, !query.isEmpty else {
                return result(.string("Missing query."), isError: true)
            }
            progress(.searching(query))
            return result(.string(Self.searchText(query: query, database: database, extras: request.extraFoods + request.insights.barcodes.compactMap(\.product))))
        case "measure_foods":
            guard let context = request.measurement else {
                return result(.string("No on-device measurements exist for this photo."), isError: true)
            }
            let items = Self.parseItems(call.input["items"])
            guard !items.isEmpty else { return result(.string("Give at least one item with a polygon of 3 or more points."), isError: true) }
            progress(.measuring(items.count))
            let text = Self.measure(items: items, containerNumber: call.input["container_region"]?.intValue, context: context,
                                    photoWidth: request.insights.photoWidth, photoHeight: request.insights.photoHeight)
            return result(.string(text))
        case "zoom_photo":
            guard let zoomer = request.zoomer,
                  let x = call.input["x"]?.doubleValue, let y = call.input["y"]?.doubleValue,
                  let width = call.input["width"]?.doubleValue, let height = call.input["height"]?.doubleValue,
                  width > 1, height > 1
            else { return result(.string("Zoom needs x, y, width and height in image 1 pixels."), isError: true) }
            progress(.zooming)
            guard let jpeg = await zoomer.zoom(x: x, y: y, width: width, height: height) else {
                return result(.string("That region could not be cropped."), isError: true)
            }
            return result(.array([
                AnalysisPrompt.imageBlock(jpeg: jpeg),
                .obj(["type": .string("text"), "text": .string("Full-resolution crop of image 1 at x \(Int(x)), y \(Int(y)), \(Int(width))×\(Int(height)) px.")]),
            ]))
        default:
            return result(.string("Unknown tool \(call.name)."), isError: true)
        }
    }

    static func searchText(query: String, database: FoodDatabase, extras: [FoodRecord]) -> String {
        let words = TextNormalizer.queryTokens(query)
        let extraHits = extras.filter { record in
            let tokens = Set(TextNormalizer.tokens(record.name))
            return words.contains { tokens.contains($0) }
        }
        let hits = extraHits + database.search(query, limit: 8).map(\.record)
        guard !hits.isEmpty else { return "No match for \"\(query)\". Try other words (for example the main ingredient and how it is cooked)." }
        return hits.prefix(8).map { record in
            let n = record.per100g
            var energy = "\(AnalysisPrompt.number(n.kcal)) kcal"
            if let range = record.kcalRange {
                energy += " (merged variants \(AnalysisPrompt.number(range.lowerBound))–\(AnalysisPrompt.number(range.upperBound)) kcal)"
            }
            return "id=\(record.id) | \(record.name) | per 100 g: \(energy), protein \(AnalysisPrompt.number(n.protein, digits: 1)) g, carbs \(AnalysisPrompt.number(n.carbs, digits: 1)) g, fat \(AnalysisPrompt.number(n.fat, digits: 1)) g"
        }.joined(separator: "\n")
    }

    static func parseItems(_ value: JSONValue?) -> [(label: String, polygon: [(x: Double, y: Double)])] {
        var items: [(label: String, polygon: [(x: Double, y: Double)])] = []
        for item in value?.arrayValue ?? [] {
            var points: [(x: Double, y: Double)] = []
            for point in item["polygon"]?.arrayValue ?? [] {
                guard let pair = point.arrayValue, pair.count >= 2, let x = pair[0].doubleValue, let y = pair[1].doubleValue else { continue }
                points.append((x: x, y: y))
            }
            if points.count >= 3 {
                items.append((label: item["label"]?.stringValue ?? "item", polygon: points))
            }
        }
        return items
    }

    static func measure(items: [(label: String, polygon: [(x: Double, y: Double)])], containerNumber: Int?,
                        context: MeasurementContext, photoWidth: Int, photoHeight: Int) -> String {
        let masks = items.map { RegionMask(polygon: $0.polygon, photoWidth: photoWidth, photoHeight: photoHeight) }
        let union = masks.dropFirst().reduce(masks[0]) { $0.union($1) }
        let container = containerNumber.flatMap { number in context.regions.first { $0.number == number }?.mask }
        let method = context.measurer.heightField == nil ? "plane_projection" : "depth"

        var itemValues: [JSONValue] = []
        var dish: ContainerMeasurement?
        for (item, mask) in zip(items, masks) {
            let m = context.measurer.measure(item: mask, container: container, otherItems: union)
            dish = dish ?? m.container
            var fields: [JSONValue.Field] = [.init("label", .string(item.label)), .init("area_cm2", .number(m.areaCm2.rounded(toPlaces: 1)))]
            if let v = m.volumeAboveFloorMl { fields.append(.init("volume_above_floor_ml", .number(v.rounded(toPlaces: 0)))) }
            if let v = m.volumeAboveTableMl { fields.append(.init("volume_above_table_ml", .number(v.rounded(toPlaces: 0)))) }
            if let h = m.medianHeightMm { fields.append(.init("median_height_mm", .number(h.rounded(toPlaces: 0)))) }
            if let h = m.p90HeightMm { fields.append(.init("p90_height_mm", .number(h.rounded(toPlaces: 0)))) }
            if let h = m.maxHeightMm { fields.append(.init("max_height_mm", .number(h.rounded(toPlaces: 0)))) }
            if let share = m.measuredShare { fields.append(.init("depth_measured_share", .number(share.rounded(toPlaces: 2)))) }
            itemValues.append(.object(fields))
        }
        var fields: [JSONValue.Field] = [.init("method", .string(method))]
        if method == "plane_projection" {
            fields.append(.init("note", .string("No depth for this photo: areas are real, heights are not measured.")))
        }
        if let dish {
            fields.append(.init("container_width_cm", .number(dish.diameterCm.rounded(toPlaces: 1))))
            if let floor = dish.floorHeightMm { fields.append(.init("plate_floor_height_mm", .number(floor.rounded(toPlaces: 0)))) }
            if let rim = dish.rimHeightMm { fields.append(.init("container_rim_height_mm", .number(rim.rounded(toPlaces: 0)))) }
        } else if containerNumber != nil, container == nil {
            fields.append(.init("note_container", .string("Region \(containerNumber!) does not exist; measured against the table only.")))
        }
        fields.append(.init("items", .array(itemValues)))
        return JSONValue.object(fields).jsonString
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
