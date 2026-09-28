import Foundation
import LooseweightKit
import Observation
import Security
import UIKit

enum AIMode: String, CaseIterable, Identifiable {
    case demo
    case cloud
    case personalKey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .demo: "Demo (no internet)"
        case .cloud: "Looseweight Cloud"
        case .personalKey: "My Anthropic API key"
        }
    }
}

/// App-wide state: the user's profile, AI connection settings and shared services.
@MainActor
@Observable
final class AppModel {
    var profile: UserProfile? {
        didSet { save(profile, key: Keys.profile) }
    }
    var aiMode: AIMode {
        didSet { defaults.set(aiMode.rawValue, forKey: Keys.aiMode) }
    }
    var effort: AnalysisEffort {
        didSet { defaults.set(effort.rawValue, forKey: Keys.effort) }
    }
    var proxyURL: String {
        didSet { defaults.set(proxyURL, forKey: Keys.proxyURL) }
    }
    var modelOverride: String {
        didSet { defaults.set(modelOverride, forKey: Keys.modelOverride) }
    }
    var cuisineHint: String {
        didSet { defaults.set(cuisineHint, forKey: Keys.cuisine) }
    }
    private(set) var hasAPIKey: Bool
    private(set) var hasProxyToken: Bool
    var lastModelID: String?

    let modelSelector = ModelSelector()
    let isUITest: Bool
    private let defaults: UserDefaults

    private enum Keys {
        static let profile = "lw.profile"
        static let aiMode = "lw.aiMode"
        static let effort = "lw.effort"
        static let proxyURL = "lw.proxyURL"
        static let modelOverride = "lw.modelOverride"
        static let cuisine = "lw.cuisine"
        static let apiKey = "anthropic-api-key"
        static let proxyToken = "proxy-token"
    }

    init(defaults: UserDefaults = .standard, arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.defaults = defaults
        isUITest = arguments.contains("-uiTest")
        if arguments.contains("-resetState") {
            for key in [Keys.profile, Keys.aiMode, Keys.effort, Keys.proxyURL, Keys.modelOverride, Keys.cuisine] {
                defaults.removeObject(forKey: key)
            }
        }
        let bundledProxy = (Bundle.main.object(forInfoDictionaryKey: "LWProxyURL") as? String) ?? ""
        let bundledToken = (Bundle.main.object(forInfoDictionaryKey: "LWProxyToken") as? String) ?? ""
        if Keychain.read(Keys.proxyToken) == nil, !bundledToken.isEmpty { Keychain.write(bundledToken, for: Keys.proxyToken) }

        profile = Self.load(UserProfile.self, key: Keys.profile, defaults: defaults)
        proxyURL = defaults.string(forKey: Keys.proxyURL) ?? bundledProxy
        let defaultMode: AIMode = bundledProxy.isEmpty ? .demo : .cloud
        aiMode = AIMode(rawValue: defaults.string(forKey: Keys.aiMode) ?? "") ?? defaultMode
        effort = AnalysisEffort(rawValue: defaults.string(forKey: Keys.effort) ?? "") ?? .high
        modelOverride = defaults.string(forKey: Keys.modelOverride) ?? ""
        cuisineHint = defaults.string(forKey: Keys.cuisine) ?? ""
        hasAPIKey = Keychain.read(Keys.apiKey) != nil
        hasProxyToken = Keychain.read(Keys.proxyToken) != nil
        if isUITest { aiMode = .demo }
    }

    // MARK: Targets

    var targets: DailyTargets? {
        profile.map { EnergyModel.targets(for: $0) }
    }

    func targets(maintenance: MaintenanceEstimate?) -> DailyTargets? {
        guard let profile else { return nil }
        return EnergyModel.targets(for: profile, maintenanceOverride: maintenance?.source == .blended ? maintenance?.kcal : nil)
    }

    // MARK: AI connection

    func setAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { Keychain.delete(Keys.apiKey) } else { Keychain.write(trimmed, for: Keys.apiKey) }
        hasAPIKey = Keychain.read(Keys.apiKey) != nil
    }

    func setProxyToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { Keychain.delete(Keys.proxyToken) } else { Keychain.write(trimmed, for: Keys.proxyToken) }
        hasProxyToken = Keychain.read(Keys.proxyToken) != nil
    }

    /// Nil in demo mode or when the chosen connection is not set up yet.
    var connection: AIConnection? {
        switch aiMode {
        case .demo:
            return nil
        case .personalKey:
            return Keychain.read(Keys.apiKey).map { AIConnection.anthropic(apiKey: $0) }
        case .cloud:
            guard let url = URL(string: proxyURL.trimmingCharacters(in: .whitespaces)), url.scheme == "https",
                  let token = Keychain.read(Keys.proxyToken) else { return nil }
            let device = UIDevice.current.identifierForVendor?.uuidString ?? "unknown-device"
            return .proxy(baseURL: url, appToken: token, deviceID: device)
        }
    }

    var connectionProblem: String? {
        switch aiMode {
        case .demo: "Demo mode shows a sample result. Connect the AI in Settings for real analysis."
        case .personalKey: hasAPIKey ? nil : "Add your Anthropic API key in Settings."
        case .cloud: connection == nil ? "Add the Looseweight Cloud address and token in Settings." : nil
        }
    }

    func resolveModel(client: ClaudeClient) async throws -> String {
        let id = try await modelSelector.modelID(client: client, override: modelOverride)
        lastModelID = id
        return id
    }

    // MARK: Persistence

    private func save<T: Encodable>(_ value: T?, key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}

/// Minimal Keychain wrapper for the API key and proxy token.
enum Keychain {
    private static let service = "io.github.haithamattiaali.looseweight"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, for account: String) {
        delete(account)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
