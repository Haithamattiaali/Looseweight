import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPRequest: Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?
    public var timeout: TimeInterval

    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil, timeout: TimeInterval = 180) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (key, value) in http?.allHeaderFields ?? [:] {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        return HTTPResponse(status: http?.statusCode ?? 0, headers: headers, body: data)
    }
}

/// Where the app sends Claude requests.
public enum AIConnection: Sendable, Hashable {
    /// Straight to Anthropic with the user's own key (kept in the Keychain on device).
    case anthropic(apiKey: String)
    /// Through the Looseweight proxy, which holds the key on the server.
    case proxy(baseURL: URL, appToken: String, deviceID: String)

    public static let anthropicBaseURL = URL(string: "https://api.anthropic.com")!
    public static let apiVersion = "2023-06-01"

    var baseURL: URL {
        switch self {
        case .anthropic: Self.anthropicBaseURL
        case let .proxy(url, _, _): url
        }
    }

    func headers(betas: [String]) -> [String: String] {
        var headers = [
            "content-type": "application/json",
            "anthropic-version": Self.apiVersion,
        ]
        switch self {
        case let .anthropic(key):
            headers["x-api-key"] = key
        case let .proxy(_, token, deviceID):
            headers["authorization"] = "Bearer \(token)"
            headers["x-device-id"] = deviceID
        }
        if !betas.isEmpty { headers["anthropic-beta"] = betas.joined(separator: ",") }
        return headers
    }

    /// `path` starts with "/" and may carry a query string.
    func url(_ path: String) -> URL {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + path)!
    }
}
