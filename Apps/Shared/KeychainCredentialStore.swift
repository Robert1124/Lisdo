import Foundation
import LisdoCore
import Security

public struct OpenAICompatibleLocalSettings: Codable, Equatable, Sendable {
    public var endpointURL: URL
    public var model: String

    public init(endpointURL: URL, model: String) {
        self.endpointURL = endpointURL
        self.model = model
    }
}

public struct DraftProviderLocalSettings: Codable, Equatable, Sendable {
    public var mode: ProviderMode
    public var endpointURL: URL?
    public var model: String
    public var displayName: String?
    public var requiresAPIKey: Bool

    public init(
        mode: ProviderMode,
        endpointURL: URL? = nil,
        model: String,
        displayName: String? = nil,
        requiresAPIKey: Bool
    ) {
        self.mode = mode
        self.endpointURL = endpointURL
        self.model = model
        self.displayName = displayName
        self.requiresAPIKey = requiresAPIKey
    }
}

public enum KeychainCredentialStoreError: Error, Equatable, Sendable {
    case emptySecret
    case encodingFailed
    case unexpectedData
    case keychainStatus(OSStatus)
}

public final class KeychainCredentialStore: @unchecked Sendable {
    public static let defaultService = "com.yiwenwu.Lisdo.credentials"

    private let service: String
    private let accessGroup: String?
    private let userDefaults: UserDefaults

    private enum Account {
        static let openAICompatibleAPIKey = "openai-compatible.api-key"

        static func apiKey(for mode: ProviderMode) -> String {
            "provider.\(mode.rawValue).api-key"
        }
    }

    private enum DefaultsKey {
        static let openAICompatibleSettings = "lisdo.openai-compatible.local-settings"

        static func providerSettings(for mode: ProviderMode) -> String {
            "lisdo.provider.\(mode.rawValue).local-settings"
        }
    }

    public init(
        service: String = KeychainCredentialStore.defaultService,
        accessGroup: String? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.service = service
        self.accessGroup = accessGroup
        self.userDefaults = userDefaults
    }

    public func saveOpenAICompatibleAPIKey(_ apiKey: String) throws {
        try saveSecret(apiKey, account: Account.openAICompatibleAPIKey)
    }

    public func readOpenAICompatibleAPIKey() throws -> String? {
        try readSecret(account: Account.openAICompatibleAPIKey)
    }

    public func deleteOpenAICompatibleAPIKey() throws {
        try deleteSecret(account: Account.openAICompatibleAPIKey)
    }

    public func saveOpenAICompatibleSettings(endpointURL: URL, model: String) throws {
        let settings = OpenAICompatibleLocalSettings(endpointURL: endpointURL, model: model)
        let data = try JSONEncoder().encode(settings)
        userDefaults.set(data, forKey: DefaultsKey.openAICompatibleSettings)
    }

    public func readOpenAICompatibleSettings() -> OpenAICompatibleLocalSettings? {
        guard let data = userDefaults.data(forKey: DefaultsKey.openAICompatibleSettings) else {
            return nil
        }
        return try? JSONDecoder().decode(OpenAICompatibleLocalSettings.self, from: data)
    }

    public func deleteOpenAICompatibleSettings() {
        userDefaults.removeObject(forKey: DefaultsKey.openAICompatibleSettings)
    }

    public func deleteOpenAICompatibleCredentialsAndSettings() throws {
        try deleteOpenAICompatibleAPIKey()
        deleteOpenAICompatibleSettings()
    }

    public func saveAPIKey(_ apiKey: String, for mode: ProviderMode) throws {
        try saveSecret(apiKey, account: Account.apiKey(for: mode))
    }

    public func readAPIKey(for mode: ProviderMode) throws -> String? {
        try readSecret(account: Account.apiKey(for: mode))
    }

    public func deleteAPIKey(for mode: ProviderMode) throws {
        try deleteSecret(account: Account.apiKey(for: mode))
    }

    public func saveProviderSettings(_ settings: DraftProviderLocalSettings) throws {
        let data = try JSONEncoder().encode(settings)
        userDefaults.set(data, forKey: DefaultsKey.providerSettings(for: settings.mode))
    }

    public func readProviderSettings(for mode: ProviderMode) -> DraftProviderLocalSettings? {
        guard let data = userDefaults.data(forKey: DefaultsKey.providerSettings(for: mode)) else {
            return nil
        }
        return try? JSONDecoder().decode(DraftProviderLocalSettings.self, from: data)
    }

    public func deleteProviderSettings(for mode: ProviderMode) {
        userDefaults.removeObject(forKey: DefaultsKey.providerSettings(for: mode))
    }

    public func deleteProviderCredentialsAndSettings(for mode: ProviderMode) throws {
        try deleteAPIKey(for: mode)
        deleteProviderSettings(for: mode)
    }

    private func saveSecret(_ secret: String, account: String) throws {
        guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KeychainCredentialStoreError.emptySecret
        }

        guard let data = secret.data(using: .utf8) else {
            throw KeychainCredentialStoreError.encodingFailed
        }

        var query = baseQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainCredentialStoreError.keychainStatus(status)
        }
    }

    private func readSecret(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainCredentialStoreError.keychainStatus(status)
        }

        guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw KeychainCredentialStoreError.unexpectedData
        }

        return secret
    }

    private func deleteSecret(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCredentialStoreError.keychainStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }
}
