import Foundation

public enum ClaudeError: Error, Equatable, Sendable {
    case http(status: Int, type: String?, message: String)
    case refused(category: String?)
    case truncated
    case invalidResponse(String)
    case noModelAvailable
    case network(String)
    case cancelled
    /// The photo shows no food or drink (or nothing that could be logged).
    case noFood(reason: String?)

    /// Short plain-English text for the user.
    public var userMessage: String {
        switch self {
        case let .http(status, _, message):
            switch status {
            case 401, 403: "The AI connection was refused. Check the key or token in Settings."
            case 429: "Too many requests right now. Try again in a minute."
            case 413: "The photo was too large to send."
            case 500...599: "The AI service is busy. Try again shortly."
            default: "The AI service returned an error (\(status)): \(message)"
            }
        case .refused: "The AI declined to analyse this photo. Try another photo or add the food by search."
        case .truncated: "The analysis was cut off. Try again."
        case .invalidResponse: "The AI answer could not be read. Try again."
        case .noModelAvailable: "No suitable AI model is available for this key."
        case .network: "No connection to the AI service. Check the internet connection."
        case .cancelled: "Cancelled."
        case .noFood: "No food found in this photo. Retake it with the meal inside the frame."
        }
    }
}

public enum ContentBlock: Sendable, Hashable {
    case text(String)
    case toolUse(id: String, name: String, input: JSONValue)
    case other(type: String)
}

public struct TokenUsage: Hashable, Sendable {
    public var input = 0
    public var output = 0
    public var cacheRead = 0
    public var cacheCreation = 0

    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(input: lhs.input + rhs.input, output: lhs.output + rhs.output,
                   cacheRead: lhs.cacheRead + rhs.cacheRead, cacheCreation: lhs.cacheCreation + rhs.cacheCreation)
    }
}

public struct MessagesResponse: Sendable {
    public let id: String
    public let model: String
    public let stopReason: String?
    public let blocks: [ContentBlock]
    /// Exact bytes of the response's `content` array, echoed back unchanged in the next turn.
    public let rawContent: Data
    public let usage: TokenUsage
    public let refusalCategory: String?

    public init(data: Data) throws {
        let value: JSONValue
        let raw: [String: Data]
        do {
            value = try JSONValue.parse(data)
            raw = try JSONValue.topLevelRawFields(data)
        } catch {
            throw ClaudeError.invalidResponse("not JSON")
        }
        guard let content = value["content"]?.arrayValue, let rawContent = raw["content"] else {
            throw ClaudeError.invalidResponse("missing content")
        }
        id = value["id"]?.stringValue ?? ""
        model = value["model"]?.stringValue ?? ""
        stopReason = value["stop_reason"]?.stringValue
        refusalCategory = value["stop_details"]?["category"]?.stringValue
        self.rawContent = rawContent
        blocks = content.map { block in
            switch block["type"]?.stringValue {
            case "text": .text(block["text"]?.stringValue ?? "")
            case "tool_use": .toolUse(id: block["id"]?.stringValue ?? "", name: block["name"]?.stringValue ?? "", input: block["input"] ?? .null)
            case let type: .other(type: type ?? "unknown")
            }
        }
        let usage = value["usage"]
        self.usage = TokenUsage(
            input: usage?["input_tokens"]?.intValue ?? 0,
            output: usage?["output_tokens"]?.intValue ?? 0,
            cacheRead: usage?["cache_read_input_tokens"]?.intValue ?? 0,
            cacheCreation: usage?["cache_creation_input_tokens"]?.intValue ?? 0
        )
    }

    public var text: String {
        blocks.compactMap { if case let .text(text) = $0 { text } else { nil } }.joined()
    }

    public var toolUses: [(id: String, name: String, input: JSONValue)] {
        blocks.compactMap { if case let .toolUse(id, name, input) = $0 { (id, name, input) } else { nil } }
    }
}

public struct ModelInfo: Hashable, Sendable {
    public var id: String
    public var displayName: String
    public var createdAt: Date?
    public var supportsImages: Bool?
    public var supportsStructuredOutputs: Bool?
}

public struct ClaudeClient: Sendable {
    public let connection: AIConnection
    public let transport: HTTPTransport
    public var maxAttempts = 3
    /// Seconds to wait between retries; injectable so tests run instantly.
    public var backoff: @Sendable (Int) async -> Void = { attempt in
        try? await Task.sleep(nanoseconds: UInt64(pow(2.5, Double(attempt)) * 1_000_000_000))
    }

    public init(connection: AIConnection, transport: HTTPTransport = URLSessionTransport()) {
        self.connection = connection
        self.transport = transport
    }

    public func createMessage(body: Data, betas: [String] = []) async throws -> MessagesResponse {
        let request = HTTPRequest(
            method: "POST",
            url: connection.url("/v1/messages"),
            headers: connection.headers(betas: betas),
            body: body,
            timeout: 240
        )
        let response = try await send(request)
        return try MessagesResponse(data: response.body)
    }

    public func listModels() async throws -> [ModelInfo] {
        let request = HTTPRequest(method: "GET", url: connection.url("/v1/models?limit=100"), headers: connection.headers(betas: []), timeout: 30)
        let response = try await send(request)
        guard let data = (try? JSONValue.parse(response.body))?["data"]?.arrayValue else {
            throw ClaudeError.invalidResponse("models list")
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return data.compactMap { entry in
            guard let id = entry["id"]?.stringValue else { return nil }
            let created = entry["created_at"]?.stringValue.flatMap { formatter.date(from: $0) ?? plain.date(from: $0) }
            let capabilities = entry["capabilities"]
            return ModelInfo(
                id: id,
                displayName: entry["display_name"]?.stringValue ?? id,
                createdAt: created,
                supportsImages: capabilities?["image_input"]?["supported"]?.boolValue,
                supportsStructuredOutputs: capabilities?["structured_outputs"]?["supported"]?.boolValue
            )
        }
    }

    private func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var attempt = 0
        while true {
            attempt += 1
            try Task.checkCancellation()
            let response: HTTPResponse
            do {
                response = try await transport.send(request)
            } catch is CancellationError {
                throw ClaudeError.cancelled
            } catch {
                if attempt < maxAttempts { await backoff(attempt); continue }
                throw ClaudeError.network(error.localizedDescription)
            }
            if (200..<300).contains(response.status) { return response }
            let retryable = [408, 429, 500, 502, 503, 504, 529].contains(response.status)
            if retryable, attempt < maxAttempts {
                await backoff(attempt)
                continue
            }
            let error = (try? JSONValue.parse(response.body))?["error"]
            throw ClaudeError.http(
                status: response.status,
                type: error?["type"]?.stringValue,
                message: error?["message"]?.stringValue ?? String(decoding: response.body.prefix(300), as: UTF8.self)
            )
        }
    }
}

public enum ModelResolver {
    /// Newest model of `family` that accepts images and structured output. Capabilities that the
    /// API does not report are treated as supported.
    public static func pickBest(from models: [ModelInfo], preferredFamilies: [String] = ["opus", "sonnet"]) -> ModelInfo? {
        for family in preferredFamilies {
            let candidates = models.filter {
                $0.id.lowercased().contains(family) && $0.supportsImages != false && $0.supportsStructuredOutputs != false
            }
            if let best = candidates.max(by: { ($0.createdAt ?? .distantPast, $0.id) < ($1.createdAt ?? .distantPast, $1.id) }) {
                return best
            }
        }
        return nil
    }
}
