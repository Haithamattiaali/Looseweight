import Foundation
import Testing
@testable import LooseweightKit

final class MockTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [HTTPRequest] = []
    private let handler: @Sendable (HTTPRequest, Int) -> HTTPResponse

    init(handler: @escaping @Sendable (HTTPRequest, Int) -> HTTPResponse) {
        self.handler = handler
    }

    var requests: [HTTPRequest] {
        lock.withLock { captured }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let number = lock.withLock {
            captured.append(request)
            return captured.count
        }
        return handler(request, number)
    }
}

enum Fixtures {
    static func json(_ text: String) -> Data { Data(text.utf8) }

    static let riceID: String = FoodDatabase.shared.search("rice white long grain cooked", limit: 1)[0].record.id

    /// First turn: the model searches and measures.
    static let toolTurn = """
    {"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-test-9","stop_reason":"tool_use",
     "content":[{"type":"thinking","thinking":"","signature":"sig-abc=="},
                {"type":"tool_use","id":"toolu_1","name":"search_foods","input":{"query":"rice white cooked"}},
                {"type":"tool_use","id":"toolu_2","name":"measure_foods","input":{"container_region":1,"items":[{"label":"rice","polygon":[[600,700],[1100,700],[1100,1100],[600,1100]]}]}}],
     "usage":{"input_tokens":5000,"output_tokens":300,"cache_read_input_tokens":0,"cache_creation_input_tokens":4000}}
    """

    static func finalTurn(foodID: String) -> String {
        let answer = """
        {"meal_title":"Rice","items":[{"name":"White rice","food_id":"\(foodID)","grams":150,"grams_low":130,"grams_high":170,"method":"depth_volume","volume_ml":250,"density_g_per_ml":0.75,"per_100g":{"kcal":130,"protein_g":2.7,"carbs_g":28,"fat_g":0.3},"confidence":0.8,"region_numbers":[1],"polygon":[[600,700],[1100,700],[1100,1100]],"is_hidden_ingredient":false,"notes":""}],"overall_confidence":0.8,"clarifying_question":null,"warnings":[]}
        """
        let escaped = answer.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        {"id":"msg_2","type":"message","role":"assistant","model":"claude-opus-test-9","stop_reason":"end_turn",
         "content":[{"type":"text","text":"\(escaped)"}],
         "usage":{"input_tokens":200,"output_tokens":400,"cache_read_input_tokens":5200,"cache_creation_input_tokens":0}}
        """
    }

    static func measurementContext() -> MeasurementContext {
        let plate = SyntheticScene.Solid.cylinder(base: .zero, radius: 0.12, height: 0.012)
        let mound = SyntheticScene.Solid.dome(center: Vec3(0, 0.012, 0), radius: 0.05)
        let scene = SyntheticScene(solids: [plate, mound])
        let table = Plane(normal: Vec3(0, 1, 0), through: .zero)
        var builder = HeightFieldBuilder(plane: table, center: .zero, size: 0.4)
        builder.add(scene.depthFrame(camera: TestCameras.overhead(width: 256, imageHeight: 192)))
        let photo = PhotoGeometry(camera: TestCameras.overhead(width: 1920, imageHeight: 1440), orientation: .right)
        let measurer = SceneMeasurer(plane: table, photo: photo, heightField: builder.build())
        let dish = scene.mask(of: [0, 1], photo: photo, width: 180, height: 240)
        return MeasurementContext(measurer: measurer, regions: [OnDeviceRegion(number: 1, mask: dish)])
    }
}

@Suite("Claude analysis loop")
struct AnalysisTests {
    @Test func jsonRoundTripKeepsOrderAndEscapes() throws {
        let value = JSONValue.obj(["b": .number(1), "a": .string("line\n\"quoted\" é 🍚"), "c": .array([.null, .bool(true), .number(0.25)])])
        let text = value.jsonString
        #expect(text == #"{"b":1,"a":"line\n\"quoted\" é 🍚","c":[null,true,0.25]}"#)
        #expect(try JSONValue.parse(Data(text.utf8)) == value)
        let spliced = JSONValue.obj(["raw": .raw(Data(#"{"x" : [1, 2]}"#.utf8))]).jsonString
        #expect(spliced == #"{"raw":{"x" : [1, 2]}}"#)
    }

    @Test func rawFieldsAreExactBytes() throws {
        let body = #"{"id":"m","content":[ {"type":"text", "text":"hié"} ],"usage":{}}"#
        let fields = try JSONValue.topLevelRawFields(Data(body.utf8))
        #expect(String(decoding: fields["content"]!, as: UTF8.self) == #"[ {"type":"text", "text":"hié"} ]"#)
    }

    @Test func modelResolverPrefersNewestCapableOpus() {
        let models = [
            ModelInfo(id: "claude-opus-test-1", displayName: "", createdAt: Date(timeIntervalSince1970: 100), supportsImages: true, supportsStructuredOutputs: true),
            ModelInfo(id: "claude-opus-test-2", displayName: "", createdAt: Date(timeIntervalSince1970: 300), supportsImages: false, supportsStructuredOutputs: true),
            ModelInfo(id: "claude-opus-test-3", displayName: "", createdAt: Date(timeIntervalSince1970: 200), supportsImages: nil, supportsStructuredOutputs: nil),
            ModelInfo(id: "claude-sonnet-test-4", displayName: "", createdAt: Date(timeIntervalSince1970: 400), supportsImages: true, supportsStructuredOutputs: true),
        ]
        #expect(ModelResolver.pickBest(from: models)?.id == "claude-opus-test-3")
        #expect(ModelResolver.pickBest(from: models.filter { !$0.id.contains("opus") })?.id == "claude-sonnet-test-4")
        #expect(ModelResolver.pickBest(from: []) == nil)
    }

    @Test func fullLoopSearchesMeasuresAndChecksTheArithmetic() async throws {
        let riceID = Fixtures.riceID
        let transport = MockTransport { request, number in
            number == 1
                ? HTTPResponse(status: 200, body: Fixtures.json(Fixtures.toolTurn))
                : HTTPResponse(status: 200, body: Fixtures.json(Fixtures.finalTurn(foodID: riceID)))
        }
        var client = ClaudeClient(connection: .anthropic(apiKey: "test-key"), transport: transport)
        client.backoff = { _ in }
        let analyzer = MealAnalyzer(client: client, database: .shared)
        let request = AnalysisRequest(
            photoJPEG: Data([0xFF, 0xD8, 0xFF]),
            insights: CaptureInsights(photoWidth: 1440, photoHeight: 1920, deviceHasLiDAR: true),
            measurement: Fixtures.measurementContext()
        )
        let outcome = try await analyzer.analyze(request, model: "claude-opus-test-9")

        #expect(outcome.turns == 2)
        #expect(outcome.toolCalls == ["search_foods", "measure_foods"])
        #expect(outcome.usage.cacheRead == 5200)
        let item = try #require(outcome.estimate.items.first)
        // 250 mL × 0.75 g/mL = 187.5 g differs from the model's 150 g by > 10 %, so the app recomputes.
        #expect(item.grams == 188)
        #expect(item.flags.contains(.gramsRecomputed))
        #expect(item.food?.id == riceID)
        #expect(abs(item.nutrients.kcal - 1.88 * FoodDatabase.shared.record(id: riceID)!.per100g.kcal) < 1)
        #expect(outcome.estimate.usedDepth)

        let requests = transport.requests
        #expect(requests.count == 2)
        #expect(requests[0].headers["x-api-key"] == "test-key")
        #expect(requests[0].headers["anthropic-beta"] == MealAnalyzer.fallbackBeta)
        let first = try JSONValue.parse(requests[0].body!)
        #expect(first["fallbacks"]?.stringValue == "default")
        #expect(first["output_config"]?["format"]?["type"]?.stringValue == "json_schema")
        #expect(first["output_config"]?["effort"]?.stringValue == "high")
        #expect(first["system"]?.arrayValue?.first?["cache_control"] != nil)
        #expect(first["cache_control"] != nil)
        #expect(first["tools"]?.arrayValue?.compactMap { $0["name"]?.stringValue } == ["search_foods", "measure_foods"])

        // Second request: history is append-only and the assistant turn is echoed byte-for-byte.
        let secondBody = String(decoding: requests[1].body!, as: UTF8.self)
        let originalContent = String(decoding: try JSONValue.topLevelRawFields(Fixtures.json(Fixtures.toolTurn))["content"]!, as: UTF8.self)
        #expect(secondBody.contains(originalContent))
        let second = try JSONValue.parse(requests[1].body!)
        let messages = try #require(second["messages"]?.arrayValue)
        #expect(messages.count == 3)
        let results = try #require(messages[2]["content"]?.arrayValue)
        #expect(results.compactMap { $0["tool_use_id"]?.stringValue } == ["toolu_1", "toolu_2"])
        let searchResult = results[0]["content"]?.stringValue ?? ""
        #expect(searchResult.contains("id=\(riceID)"))
        let measureResult = try JSONValue.parse(Data((results[1]["content"]?.stringValue ?? "").utf8))
        #expect(measureResult["method"]?.stringValue == "depth")
        let volume = measureResult["items"]?.arrayValue?.first?["volume_above_floor_ml"]?.doubleValue ?? 0
        #expect(volume > 150 && volume < 300, "rice volume \(volume)")
        #expect(abs((measureResult["plate_floor_height_mm"]?.doubleValue ?? 0) - 12) < 3)
    }

    @Test func refusalIsReported() async throws {
        let transport = MockTransport { _, _ in
            HTTPResponse(status: 200, body: Fixtures.json(#"{"id":"m","model":"x","stop_reason":"refusal","stop_details":{"type":"refusal","category":"cyber"},"content":[],"usage":{}}"#))
        }
        var client = ClaudeClient(connection: .anthropic(apiKey: "k"), transport: transport)
        client.backoff = { _ in }
        let analyzer = MealAnalyzer(client: client, database: .shared)
        await #expect(throws: ClaudeError.refused(category: "cyber")) {
            _ = try await analyzer.analyze(AnalysisRequest(photoJPEG: Data([1]), insights: CaptureInsights(photoWidth: 10, photoHeight: 10)), model: "m")
        }
    }

    @Test func rejectedFallbackIsDroppedOnceAndBusyIsRetried() async throws {
        let riceID = Fixtures.riceID
        let transport = MockTransport { request, number in
            switch number {
            case 1: HTTPResponse(status: 400, body: Fixtures.json(#"{"type":"error","error":{"type":"invalid_request_error","message":"fallbacks: not supported for this model"}}"#))
            case 2: HTTPResponse(status: 529, body: Fixtures.json(#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#))
            default: HTTPResponse(status: 200, body: Fixtures.json(Fixtures.finalTurn(foodID: riceID)))
            }
        }
        var client = ClaudeClient(connection: .proxy(baseURL: URL(string: "https://proxy.example.com/")!, appToken: "tok", deviceID: "device-1234"), transport: transport)
        client.backoff = { _ in }
        let analyzer = MealAnalyzer(client: client, database: .shared)
        let outcome = try await analyzer.analyze(AnalysisRequest(photoJPEG: Data([1]), insights: CaptureInsights(photoWidth: 10, photoHeight: 10)), model: "m")
        #expect(outcome.estimate.items.count == 1)
        let requests = transport.requests
        #expect(requests.count == 3)
        #expect(requests[0].url.absoluteString == "https://proxy.example.com/v1/messages")
        #expect(requests[0].headers["authorization"] == "Bearer tok")
        #expect(requests[0].headers["x-api-key"] == nil)
        #expect(requests[2].headers["anthropic-beta"] == nil)
        #expect(try JSONValue.parse(requests[2].body!)["fallbacks"] == nil)
    }

    @Test func modelSelectorCachesAndHonoursOverride() async throws {
        let transport = MockTransport { _, _ in
            HTTPResponse(status: 200, body: Fixtures.json(#"{"data":[{"id":"claude-opus-test-1","display_name":"A","created_at":"2026-01-01T00:00:00Z","capabilities":{"image_input":{"supported":true},"structured_outputs":{"supported":true}}},{"id":"claude-opus-test-2","display_name":"B","created_at":"2026-05-01T00:00:00Z"}]}"#))
        }
        let client = ClaudeClient(connection: .anthropic(apiKey: "k"), transport: transport)
        let selector = ModelSelector()
        #expect(try await selector.modelID(client: client) == "claude-opus-test-2")
        #expect(try await selector.modelID(client: client) == "claude-opus-test-2")
        #expect(transport.requests.count == 1)
        #expect(try await selector.modelID(client: client, override: "custom-model") == "custom-model")
    }

    @Test func resolverClampsMergedRangesAndFlagsMismatches() throws {
        let ranged = try #require(FoodDatabase.shared.records.first { ($0.kcalRange?.upperBound ?? 0) - ($0.kcalRange?.lowerBound ?? 0) > 50 })
        let range = try #require(ranged.kcalRange)
        let plain = try #require(FoodDatabase.shared.records.first { $0.kcalRange == nil && $0.per100g.kcal > 100 })
        let analysis = AIMealAnalysis(mealTitle: "t", items: [
            .init(name: "a", foodID: ranged.id, grams: 100, gramsLow: 80, gramsHigh: 120, method: .visualEstimate,
                  per100g: .init(kcal: range.upperBound + 500, proteinG: 1, carbsG: 1, fatG: 1), confidence: 0.5),
            .init(name: "b", foodID: plain.id, grams: 100, gramsLow: 80, gramsHigh: 120, method: .visualEstimate,
                  per100g: .init(kcal: plain.per100g.kcal * 3, proteinG: 1, carbsG: 1, fatG: 1), confidence: 0.5),
            .init(name: "c", foodID: "invented-id", grams: 50, gramsLow: 0, gramsHigh: 0, method: .count,
                  per100g: .init(kcal: 200, proteinG: 10, carbsG: 20, fatG: 5), confidence: 2),
            .init(name: "d", foodID: nil, grams: 0, gramsLow: 0, gramsHigh: 0, method: .count,
                  per100g: .init(kcal: 200, proteinG: 10, carbsG: 20, fatG: 5), confidence: 0.5),
        ], overallConfidence: 0.7)
        let estimate = NutritionResolver.resolve(analysis, database: .shared)
        #expect(estimate.items.count == 3)
        #expect(abs(estimate.items[0].per100g.kcal - range.upperBound) < 0.001)
        #expect(estimate.items[1].flags.contains(.checkMatch))
        #expect(estimate.items[1].per100g == plain.per100g)
        #expect(estimate.items[2].flags.contains(.aiEstimate))
        #expect(estimate.items[2].gramsLow == 38 && estimate.items[2].gramsHigh == 63)
        #expect(estimate.items[2].confidence == 1)
    }

    @Test func decodesAnswerWrappedInProse() throws {
        let text = "Here you go:\n" + #"{"meal_title":"x","items":[],"overall_confidence":0.5,"clarifying_question":null,"warnings":["w"]}"# + "\nThanks"
        let analysis = try AIMealAnalysis.decode(from: text)
        #expect(analysis.warnings == ["w"])
        #expect(throws: ClaudeError.self) { try AIMealAnalysis.decode(from: "no json here") }
    }

    @Test func reportDescribesOnDeviceFindings() {
        let insights = CaptureInsights(
            photoWidth: 1440, photoHeight: 1920, deviceHasLiDAR: true,
            scale: ScaleReport(cameraHeightCm: 38, tiltDegrees: 9, pixelsPerCmAtTable: 36.5, hasDepth: true, depthFramesFused: 14, depthCoverage: 0.93),
            classifierLabels: [ClassifierLabel(label: "rice", confidence: 0.61)],
            recognizedText: ["Nutrition Facts", "Calories 250"],
            qualityWarnings: ["the photo looks blurry"],
            mealName: "lunch",
            userNote: "cooked with 1 tbsp olive oil",
            portionHints: [PortionHint(food: "Basmati rice", typicalGrams: 180, timesLogged: 4)]
        )
        let report = AnalysisPrompt.report(for: insights)
        for fragment in ["1440×1920", "38 cm above", "36.5 px per cm", "14 frames", "93%", "rice 0.61", "Calories 250", "blurry", "lunch", "180 g (4×)", "olive oil"] {
            #expect(report.contains(fragment), "missing \(fragment)")
        }
    }

    @Test func outputSchemaIsStrictEverywhere() {
        func check(_ schema: JSONValue, path: String) {
            if schema["type"]?.stringValue == "object" {
                #expect(schema["additionalProperties"] == .bool(false), "\(path) allows extra keys")
                let properties = schema["properties"].flatMap { value -> [String]? in
                    if case let .object(fields) = value { return fields.map(\.key) }
                    return nil
                } ?? []
                let required = schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
                #expect(Set(properties) == Set(required), "\(path) required mismatch")
                if case let .object(fields)? = schema["properties"] {
                    for field in fields { check(field.value, path: path + "." + field.key) }
                }
            }
            if let items = schema["items"] { check(items, path: path + "[]") }
        }
        check(AnalysisPrompt.outputSchema, path: "output")
        for tool in [AnalysisPrompt.searchTool, AnalysisPrompt.measureTool, AnalysisPrompt.zoomTool] {
            check(tool["input_schema"]!, path: tool["name"]!.stringValue!)
        }
    }
}

@Suite("Barcode and photo quality")
struct BarcodeAndQualityTests {
    @Test func parsesOpenFoodFactsProduct() throws {
        let body = #"{"status":1,"product":{"product_name":"Laban","brands":"Almarai, Other","nutriments":{"energy-kcal_100g":47,"proteins_100g":3.1,"carbohydrates_100g":4.8,"fat_100g":1.5,"sodium_100g":0.05}}}"#
        let record = try #require(OpenFoodFactsClient.parse(Data(body.utf8), barcode: "6281007000000"))
        #expect(record.id == "off:6281007000000")
        #expect(record.name == "Almarai — Laban")
        #expect(record.per100g.kcal == 47)
        #expect(record.sodiumMg == 50)
        #expect(OpenFoodFactsClient.parse(Data(#"{"status":0}"#.utf8), barcode: "1") == nil)
        let kilojoules = #"{"status":1,"product":{"product_name":"X","nutriments":{"energy_100g":418.4}}}"#
        #expect(OpenFoodFactsClient.parse(Data(kilojoules.utf8), barcode: "1")?.per100g.kcal == 100)
    }

    @Test func sharpnessSeparatesSharpFromBlurry() {
        let width = 128, height = 128
        var sharp = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height { for x in 0..<width { sharp[y * width + x] = ((x / 4 + y / 4) % 2 == 0) ? 230 : 25 } }
        var blurry = sharp
        for _ in 0..<8 {
            var next = blurry
            for y in 0..<height {
                for x in 0..<width {
                    var sum = 0
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let yy = min(max(y + dy, 0), height - 1), xx = min(max(x + dx, 0), width - 1)
                            sum += Int(blurry[yy * width + xx])
                        }
                    }
                    next[y * width + x] = UInt8(sum / 9)
                }
            }
            blurry = next
        }
        #expect(ImageQuality.laplacianVariance(gray: sharp, width: width, height: height) > 1000)
        #expect(ImageQuality.laplacianVariance(gray: blurry, width: width, height: height) < ImageQuality.blurThreshold)
        #expect(ImageQuality.warnings(gray: blurry, width: width, height: height).contains("the photo looks blurry"))
        #expect(ImageQuality.warnings(gray: [UInt8](repeating: 10, count: 100), width: 10, height: 10).contains("the photo is very dark"))
    }
}
