import Foundation
import LisdoCore

public enum LisdoAccountSessionServiceError: Error, Equatable, Sendable {
    case missingLisdoEndpoint
    case missingBackendSessionToken
}

public struct LisdoAccountSessionSummary: Codable, Equatable, Sendable {
    public var accountID: String
    public var email: String?
    public var fullName: String?
    public var appleSubject: String?
    public var signedInAt: Date

    public init(accountID: String, email: String?, fullName: String? = nil, appleSubject: String?, signedInAt: Date) {
        self.accountID = accountID
        self.email = email
        self.fullName = fullName
        self.appleSubject = appleSubject
        self.signedInAt = signedInAt
    }

    public var displayLabel: String {
        if let email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return email
        }
        return "Account \(accountID.suffix(8))"
    }
}

extension LisdoAccountSessionServiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingLisdoEndpoint:
            return "Lisdo endpoint is not configured."
        case .missingBackendSessionToken:
            return "Lisdo account session did not include a server token."
        }
    }
}

public struct LisdoAccountSessionService: Sendable {
    private let credentialStore: KeychainCredentialStore
    private let providerFactory: DraftProviderFactory

    private enum DefaultsKey {
        static let accountSummary = "lisdo.account.session-summary"
    }

    public init(
        credentialStore: KeychainCredentialStore = KeychainCredentialStore(),
        providerFactory: DraftProviderFactory = DraftProviderFactory()
    ) {
        self.credentialStore = credentialStore
        self.providerFactory = providerFactory
    }

    public func currentLisdoEndpointURL() -> URL? {
        providerFactory.loadSettings(for: .lisdoManaged).endpointURL
            ?? DraftProviderFactory.metadata(for: .lisdoManaged).defaultEndpointURL
    }

    public func currentLisdoBearerToken() -> String? {
        let token = providerFactory.loadSettings(for: .lisdoManaged).bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token, !token.isEmpty, token != "dev-token" else {
            return nil
        }
        return token
    }

    public func currentAccountSummary() -> LisdoAccountSessionSummary? {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.accountSummary) else {
            return nil
        }
        return try? JSONDecoder().decode(LisdoAccountSessionSummary.self, from: data)
    }

    public func refreshAccountSummaryFromBackend() async throws -> LisdoAccountSessionSummary? {
        guard let endpointURL = currentLisdoEndpointURL(),
              let token = currentLisdoBearerToken()
        else {
            return currentAccountSummary()
        }

        let response = try await LisdoBackendClient(baseURL: endpointURL, bearerToken: token).bootstrap()
        guard let accountID = stringField("id", in: response.account) else {
            return currentAccountSummary()
        }

        let currentSummary = currentAccountSummary()
        let summary = LisdoAccountSessionSummary(
            accountID: accountID,
            email: currentSummary?.email,
            fullName: currentSummary?.fullName,
            appleSubject: currentSummary?.appleSubject,
            signedInAt: currentSummary?.signedInAt ?? Date()
        )
        saveAccountSummary(summary)
        return summary
    }

    public func authenticateWithApple(identityToken: String, authorizationCode: String? = nil, fullName: String? = nil) async throws -> LisdoBackendAuthResponse {
        guard let endpointURL = currentLisdoEndpointURL() else {
            throw LisdoAccountSessionServiceError.missingLisdoEndpoint
        }

        let response = try await LisdoBackendClient(baseURL: endpointURL, bearerToken: "")
            .authenticateWithApple(identityToken: identityToken, authorizationCode: authorizationCode)
        try saveSessionToken(response.session.token, endpointURL: endpointURL)
        saveAccountSummary(response: response, identityToken: identityToken, fullName: fullName)
        return response
    }

    public func verifyStoreKitTransaction(_ request: LisdoStoreKitTransactionVerificationRequest) async throws -> LisdoStoreKitTransactionVerificationResponse {
        guard let endpointURL = currentLisdoEndpointURL() else {
            throw LisdoAccountSessionServiceError.missingLisdoEndpoint
        }
        guard let token = currentLisdoBearerToken() else {
            throw LisdoAccountSessionServiceError.missingBackendSessionToken
        }

        return try await LisdoBackendClient(baseURL: endpointURL, bearerToken: token)
            .verifyStoreKitTransaction(request)
    }

    public func saveSessionToken(_ token: String, endpointURL: URL? = nil) throws {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw LisdoAccountSessionServiceError.missingBackendSessionToken
        }

        let metadata = DraftProviderFactory.metadata(for: .lisdoManaged)
        let settings = DraftProviderLocalSettings(
            mode: .lisdoManaged,
            endpointURL: endpointURL ?? currentLisdoEndpointURL() ?? metadata.defaultEndpointURL,
            model: metadata.defaultModel,
            displayName: "Lisdo",
            requiresAPIKey: false,
            bearerToken: trimmedToken
        )
        try credentialStore.saveProviderSettings(settings)
    }

    public func signOut() throws {
        let metadata = DraftProviderFactory.metadata(for: .lisdoManaged)
        let currentSettings = providerFactory.loadSettings(for: .lisdoManaged)
        let settings = DraftProviderLocalSettings(
            mode: .lisdoManaged,
            endpointURL: currentSettings.endpointURL ?? metadata.defaultEndpointURL,
            model: currentSettings.model.isEmpty ? metadata.defaultModel : currentSettings.model,
            displayName: "Lisdo",
            requiresAPIKey: false,
            bearerToken: nil
        )
        try credentialStore.saveProviderSettings(settings)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.accountSummary)
    }

    private func saveAccountSummary(response: LisdoBackendAuthResponse, identityToken: String, fullName: String?) {
        let claims = appleIdentityTokenClaims(from: identityToken)
        let summary = LisdoAccountSessionSummary(
            accountID: response.account.id,
            email: claims.email,
            fullName: normalizedOptionalString(fullName),
            appleSubject: claims.subject,
            signedInAt: Date()
        )
        saveAccountSummary(summary)
    }

    private func normalizedOptionalString(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func saveAccountSummary(_ summary: LisdoAccountSessionSummary) {
        if let data = try? JSONEncoder().encode(summary) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.accountSummary)
        }
    }

    private func stringField(_ key: String, in value: LisdoBackendJSONValue?) -> String? {
        guard case .object(let object)? = value,
              case .string(let string)? = object[key]
        else {
            return nil
        }
        return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : string
    }

    private func appleIdentityTokenClaims(from identityToken: String) -> (email: String?, subject: String?) {
        let segments = identityToken.split(separator: ".")
        guard segments.count == 3,
              let payloadData = base64URLDecodedData(String(segments[1])),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else {
            return (nil, nil)
        }

        let email = (payload["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = (payload["sub"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            email?.isEmpty == false ? email : nil,
            subject?.isEmpty == false ? subject : nil
        )
    }

    private func base64URLDecodedData(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingLength = (4 - base64.count % 4) % 4
        if paddingLength > 0 {
            base64.append(String(repeating: "=", count: paddingLength))
        }
        return Data(base64Encoded: base64)
    }
}
