import Foundation
import LisdoCore

public enum LisdoBackendClientError: Error, Equatable, Sendable {
    case invalidHTTPResponse
    case httpStatus(Int)
    case backendError(statusCode: Int, code: String, message: String)
    case invalidDraftJSONObject
}

extension LisdoBackendClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "Lisdo did not receive a valid server response. Try again."
        case .backendError(_, _, let message):
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedMessage.isEmpty ? "Lisdo server returned an error." : trimmedMessage
        case .httpStatus(401), .httpStatus(403):
            return "Lisdo could not authenticate this account. Sign in again or refresh Lisdo."
        case .httpStatus(402):
            return "Lisdo quota is not available for this account. Upgrade your plan, buy a top-up, or choose another provider."
        case .httpStatus(429):
            return "Lisdo is temporarily rate limited. Try again in a moment."
        case .httpStatus(let statusCode) where (500..<600).contains(statusCode):
            return "Lisdo server is temporarily unavailable. Try again in a moment."
        case .httpStatus(let statusCode):
            return "Lisdo server returned HTTP \(statusCode)."
        case .invalidDraftJSONObject:
            return "Lisdo returned a draft response that could not be read."
        }
    }
}

extension LisdoBackendClientError: TaskDraftProviderRetryClassifying {
    public var taskDraftRetryClassification: TaskDraftProviderRetryClassification {
        switch self {
        case .backendError(let statusCode, _, _):
            return TaskDraftProviderOutputRetry.isTransientHTTPStatus(statusCode) ? .retryableTransient : .nonRetryable
        case .httpStatus(let statusCode):
            return TaskDraftProviderOutputRetry.isTransientHTTPStatus(statusCode) ? .retryableTransient : .nonRetryable
        case .invalidHTTPResponse:
            return .retryableTransient
        case .invalidDraftJSONObject:
            return .nonRetryable
        }
    }
}

public struct LisdoBackendClient {
    public var baseURL: URL
    public var bearerToken: String

    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        baseURL: URL,
        bearerToken: String,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.urlSession = urlSession
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func bootstrap() async throws -> LisdoBackendBootstrapResponse {
        try await send(pathComponents: ["bootstrap"], method: "GET", body: Optional<Data>.none)
    }

    public func authenticateWithApple(identityToken: String, authorizationCode: String? = nil) async throws -> LisdoBackendAuthResponse {
        try await send(
            pathComponents: ["auth", "apple"],
            method: "POST",
            body: try encoder.encode(
                LisdoBackendAppleAuthRequest(
                    identityToken: identityToken,
                    authorizationCode: authorizationCode
                )
            )
        )
    }

    public func quota() async throws -> LisdoBackendQuota {
        let data = try await sendData(pathComponents: ["quota"], method: "GET", body: Optional<Data>.none)
        if let envelope = try? decoder.decode(LisdoBackendQuotaEnvelope.self, from: data) {
            return envelope.quota
        }
        return try decoder.decode(LisdoBackendQuota.self, from: data)
    }

    public func generateDraft(chatRequest: OpenAICompatibleChatRequest) async throws -> LisdoBackendDraftGenerateResponse {
        let requestBody = LisdoBackendDraftGenerateRequest(chatRequest: chatRequest)
        return try await send(
            pathComponents: ["drafts", "generate"],
            method: "POST",
            body: try encoder.encode(requestBody)
        )
    }

    public func verifyStoreKitTransaction(_ transaction: LisdoStoreKitTransactionVerificationRequest) async throws -> LisdoStoreKitTransactionVerificationResponse {
        try await send(
            pathComponents: ["storekit", "transactions", "verify"],
            method: "POST",
            body: try encoder.encode(transaction)
        )
    }

    private func send<Response: Decodable>(
        pathComponents: [String],
        method: String,
        body: Data?
    ) async throws -> Response {
        let data = try await sendData(pathComponents: pathComponents, method: method, body: body)
        return try decoder.decode(Response.self, from: data)
    }

    private func sendData(
        pathComponents: [String],
        method: String,
        body: Data?
    ) async throws -> Data {
        var request = URLRequest(url: endpoint(pathComponents))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let trimmedBearerToken = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBearerToken.isEmpty {
            request.setValue("Bearer \(trimmedBearerToken)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LisdoBackendClientError.invalidHTTPResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let envelope = try? decoder.decode(LisdoBackendErrorEnvelope.self, from: data),
               let backendError = envelope.error {
                throw LisdoBackendClientError.backendError(
                    statusCode: httpResponse.statusCode,
                    code: backendError.code,
                    message: backendError.message
                )
            }
            throw LisdoBackendClientError.httpStatus(httpResponse.statusCode)
        }

        return data
    }

    private func endpoint(_ pathComponents: [String]) -> URL {
        let relativePath = pathComponents.joined(separator: "/")
        let normalizedBasePath = baseURL.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if normalizedBasePath == relativePath || normalizedBasePath.hasSuffix("/\(relativePath)") {
            return baseURL
        }

        return pathComponents.reduce(baseURL) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }
    }
}

private struct LisdoBackendErrorEnvelope: Decodable {
    var error: LisdoBackendErrorBody?
}

private struct LisdoBackendErrorBody: Decodable {
    var code: String
    var message: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.code = (try? container.decode(String.self, forKey: .code)) ?? "server_error"
        self.message = (try? container.decode(String.self, forKey: .message)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case message
    }
}

private struct LisdoBackendAppleAuthRequest: Encodable {
    var identityToken: String
    var authorizationCode: String?
}

public struct LisdoBackendAuthResponse: Decodable, Equatable, Sendable {
    public var status: String
    public var mode: String
    public var account: LisdoBackendAccount
    public var session: LisdoBackendSession
}

public struct LisdoBackendAccount: Codable, Equatable, Sendable {
    public var id: String
    public var planId: String
}

public struct LisdoBackendSession: Codable, Equatable, Sendable {
    public var id: String
    public var subject: String
    public var token: String
    public var tokenType: String
    public var authenticated: Bool
    public var expiresAt: String?
}

public struct LisdoBackendBootstrapResponse: Decodable, Equatable, Sendable {
    public var account: LisdoBackendJSONValue?
    public var session: LisdoBackendJSONValue?
    public var entitlements: LisdoBackendEntitlements
    public var quota: LisdoBackendQuota

    public var entitlementSnapshot: LisdoEntitlementSnapshot {
        quota.entitlementSnapshot(entitlements: entitlements)
    }

    public func serverSnapshot(refreshedAt: Date = Date()) -> LisdoServerEntitlementSnapshot {
        LisdoServerEntitlementSnapshot(
            quota: quota,
            entitlements: entitlements,
            refreshedAt: refreshedAt,
            source: .bootstrap
        )
    }

    private enum CodingKeys: String, CodingKey {
        case account
        case session
        case entitlements
        case quota
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.account = try? container.decodeIfPresent(LisdoBackendJSONValue.self, forKey: .account)
        self.session = try? container.decodeIfPresent(LisdoBackendJSONValue.self, forKey: .session)
        self.quota = try container.decode(LisdoBackendQuota.self, forKey: .quota)
        self.entitlements = (try? container.decodeIfPresent(LisdoBackendEntitlements.self, forKey: .entitlements))
            ?? LisdoBackendEntitlements.inferred(planId: quota.planId, quota: quota)
    }
}

public struct LisdoBackendEntitlements: Codable, Equatable, Sendable {
    public var byokAndCLI: Bool
    public var lisdoManagedDrafts: Bool
    public var iCloudSync: Bool
    public var realtimeVoice: Bool

    public init(
        byokAndCLI: Bool,
        lisdoManagedDrafts: Bool,
        iCloudSync: Bool,
        realtimeVoice: Bool
    ) {
        self.byokAndCLI = byokAndCLI
        self.lisdoManagedDrafts = lisdoManagedDrafts
        self.iCloudSync = iCloudSync
        self.realtimeVoice = realtimeVoice
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.byokAndCLI = (try? container.decode(Bool.self, forKey: .byokAndCLI)) ?? false
        self.lisdoManagedDrafts = (try? container.decode(Bool.self, forKey: .lisdoManagedDrafts)) ?? false
        self.iCloudSync = (try? container.decode(Bool.self, forKey: .iCloudSync)) ?? false
        self.realtimeVoice = (try? container.decode(Bool.self, forKey: .realtimeVoice)) ?? false
    }

    public static func inferred(planId: String, quota: LisdoBackendQuota) -> LisdoBackendEntitlements {
        let tier = LisdoBackendQuota.resolvedPlanTier(planId: planId, quota: quota, entitlements: nil)
        return LisdoBackendEntitlements(
            byokAndCLI: true,
            lisdoManagedDrafts: tier != .free,
            iCloudSync: [.monthlyBasic, .monthlyPlus, .monthlyMax].contains(tier),
            realtimeVoice: tier == .starterTrial || tier == .monthlyMax
        )
    }
}

public struct LisdoBackendQuota: Codable, Equatable, Sendable {
    public var planId: String
    public var monthlyNonRolloverRemaining: Int
    public var topUpRolloverRemaining: Int
    public var monthlyNonRolloverConsumed: Int
    public var topUpRolloverConsumed: Int
    public var billingSource: String?

    public init(
        planId: String,
        monthlyNonRolloverRemaining: Int,
        topUpRolloverRemaining: Int,
        monthlyNonRolloverConsumed: Int,
        topUpRolloverConsumed: Int,
        billingSource: String? = nil
    ) {
        self.planId = planId
        self.monthlyNonRolloverRemaining = max(0, monthlyNonRolloverRemaining)
        self.topUpRolloverRemaining = max(0, topUpRolloverRemaining)
        self.monthlyNonRolloverConsumed = max(0, monthlyNonRolloverConsumed)
        self.topUpRolloverConsumed = max(0, topUpRolloverConsumed)
        self.billingSource = Self.normalizedBillingSource(billingSource)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            planId: ((try? container.decode(String.self, forKey: .planId)) ?? "free")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            monthlyNonRolloverRemaining: (try? container.decodeFlexibleInt(forKey: .monthlyNonRolloverRemaining)) ?? 0,
            topUpRolloverRemaining: (try? container.decodeFlexibleInt(forKey: .topUpRolloverRemaining)) ?? 0,
            monthlyNonRolloverConsumed: (try? container.decodeFlexibleInt(forKey: .monthlyNonRolloverConsumed)) ?? 0,
            topUpRolloverConsumed: (try? container.decodeFlexibleInt(forKey: .topUpRolloverConsumed)) ?? 0,
            billingSource: try? container.decode(String.self, forKey: .billingSource)
        )
    }

    public func entitlementSnapshot(entitlements: LisdoBackendEntitlements? = nil) -> LisdoEntitlementSnapshot {
        LisdoEntitlementSnapshot(
            tier: Self.resolvedPlanTier(planId: planId, quota: self, entitlements: entitlements),
            quotaBalance: LisdoQuotaBalance(
                monthlyNonRolloverUnits: monthlyNonRolloverRemaining,
                topUpRolloverUnits: topUpRolloverRemaining
            )
        )
    }

    public var totalRemaining: Int {
        monthlyNonRolloverRemaining + topUpRolloverRemaining
    }

    public var totalConsumed: Int {
        monthlyNonRolloverConsumed + topUpRolloverConsumed
    }

    public var totalCapacity: Int {
        totalRemaining + totalConsumed
    }

    public var consumedFraction: Double {
        guard totalCapacity > 0 else { return 0 }
        return min(1, max(0, Double(totalConsumed) / Double(totalCapacity)))
    }

    public var remainingFraction: Double {
        guard totalCapacity > 0 else { return 0 }
        return min(1, max(0, Double(totalRemaining) / Double(totalCapacity)))
    }

    fileprivate static func resolvedPlanTier(
        planId: String,
        quota: LisdoBackendQuota,
        entitlements: LisdoBackendEntitlements?
    ) -> LisdoPlanTier {
        let normalizedPlanId = planId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")

        switch normalizedPlanId {
        case "free", "lisdo-free":
            return .free
        case "starter", "starter-trial", "trial", "lisdo-starter-trial":
            return .starterTrial
        case "basic", "monthly-basic", "lisdo-monthly-basic":
            return .monthlyBasic
        case "plus", "monthly-plus", "lisdo-monthly-plus":
            return .monthlyPlus
        case "max", "monthly-max", "lisdo-monthly-max":
            return .monthlyMax
        default:
            if let entitlements {
                if entitlements.iCloudSync && entitlements.realtimeVoice {
                    return .monthlyMax
                }
                if entitlements.iCloudSync {
                    return inferredMonthlyTier(for: quota)
                }
                if entitlements.lisdoManagedDrafts || entitlements.realtimeVoice {
                    return .starterTrial
                }
                return .free
            }

            return inferredMonthlyTier(for: quota)
        }
    }

    private static func inferredMonthlyTier(for quota: LisdoBackendQuota) -> LisdoPlanTier {
        let monthlyUnits = quota.monthlyNonRolloverRemaining + quota.monthlyNonRolloverConsumed
        if monthlyUnits >= LisdoEntitlementSnapshot.defaultMonthlyNonRolloverUnits(for: .monthlyMax) {
            return .monthlyMax
        }
        if monthlyUnits >= LisdoEntitlementSnapshot.defaultMonthlyNonRolloverUnits(for: .monthlyPlus) {
            return .monthlyPlus
        }
        if monthlyUnits >= LisdoEntitlementSnapshot.defaultMonthlyNonRolloverUnits(for: .monthlyBasic) {
            return .monthlyBasic
        }
        if monthlyUnits > 0 || quota.topUpRolloverRemaining > 0 || quota.topUpRolloverConsumed > 0 {
            return .starterTrial
        }
        return .free
    }

    private static func normalizedBillingSource(_ value: String?) -> String? {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalized, !normalized.isEmpty else {
            return nil
        }
        return normalized
    }
}

public struct LisdoBackendDraftGenerateResponse: Decodable, Equatable, Sendable {
    public var draftJSON: String
    public var usage: LisdoBackendJSONValue?
    public var quota: LisdoBackendQuota

    private enum CodingKeys: String, CodingKey {
        case draftJSON
        case usage
        case quota
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.draftJSON = try container.decode(LisdoBackendDraftJSON.self, forKey: .draftJSON).value
        self.usage = try? container.decodeIfPresent(LisdoBackendJSONValue.self, forKey: .usage)
        self.quota = try container.decode(LisdoBackendQuota.self, forKey: .quota)
    }
}

public enum LisdoBackendJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case bool(Bool)
    case object([String: LisdoBackendJSONValue])
    case array([LisdoBackendJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: LisdoBackendJSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([LisdoBackendJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    fileprivate var foundationValue: Any {
        switch self {
        case .string(let value):
            return value
        case .integer(let value):
            return value
        case .double(let value):
            return value
        case .bool(let value):
            return value
        case .object(let value):
            return value.mapValues(\.foundationValue)
        case .array(let value):
            return value.map(\.foundationValue)
        case .null:
            return NSNull()
        }
    }
}

public enum LisdoServerEntitlementSnapshotSource: String, Codable, Equatable, Sendable {
    case bootstrap
    case quotaUpdate
    case storeKit
}

public struct LisdoServerEntitlementSnapshot: Codable, Equatable, Sendable {
    public var snapshot: LisdoEntitlementSnapshot
    public var entitlements: LisdoBackendEntitlements
    public var quota: LisdoBackendQuota
    public var refreshedAt: Date
    public var source: LisdoServerEntitlementSnapshotSource

    public init(
        quota: LisdoBackendQuota,
        entitlements: LisdoBackendEntitlements? = nil,
        refreshedAt: Date = Date(),
        source: LisdoServerEntitlementSnapshotSource
    ) {
        let resolvedEntitlements = entitlements ?? LisdoBackendEntitlements.inferred(planId: quota.planId, quota: quota)
        self.snapshot = quota.entitlementSnapshot(entitlements: resolvedEntitlements)
        self.entitlements = resolvedEntitlements
        self.quota = quota
        self.refreshedAt = refreshedAt
        self.source = source
    }
}

private struct LisdoBackendDraftGenerateRequest: Encodable {
    var chatRequest: OpenAICompatibleChatRequest
}

public struct LisdoStoreKitTransactionVerificationRequest: Encodable, Equatable, Sendable {
    public var signedTransactionInfo: String?
    public var clientVerified: Bool
    public var transactionId: String
    public var originalTransactionId: String
    public var productId: String
    public var environment: String
    public var purchaseDate: String?
    public var expirationDate: String?

    public init(
        signedTransactionInfo: String? = nil,
        clientVerified: Bool,
        transactionId: String,
        originalTransactionId: String,
        productId: String,
        environment: String,
        purchaseDate: String? = nil,
        expirationDate: String? = nil
    ) {
        self.signedTransactionInfo = signedTransactionInfo
        self.clientVerified = clientVerified
        self.transactionId = transactionId
        self.originalTransactionId = originalTransactionId
        self.productId = productId
        self.environment = environment
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
    }
}

public struct LisdoStoreKitTransactionVerificationResponse: Decodable, Equatable, Sendable {
    public var status: String
    public var mode: String
    public var entitlements: LisdoBackendEntitlements
    public var quota: LisdoBackendQuota

    public func serverSnapshot(refreshedAt: Date = Date()) -> LisdoServerEntitlementSnapshot {
        LisdoServerEntitlementSnapshot(
            quota: quota,
            entitlements: entitlements,
            refreshedAt: refreshedAt,
            source: .storeKit
        )
    }
}

private struct LisdoBackendQuotaEnvelope: Decodable {
    var quota: LisdoBackendQuota
}

private struct LisdoBackendDraftJSON: Decodable {
    var value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self.value = stringValue
            return
        }

        let jsonValue = try container.decode(LisdoBackendJSONValue.self)
        guard case .object = jsonValue else {
            throw LisdoBackendClientError.invalidDraftJSONObject
        }

        let data = try JSONSerialization.data(
            withJSONObject: jsonValue.foundationValue,
            options: [.sortedKeys]
        )
        self.value = String(data: data, encoding: .utf8) ?? "{}"
    }
}

private struct LisdoBackendFlexibleInt: Decodable {
    var value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self.value = value
            return
        }
        if let value = try? container.decode(Double.self) {
            self.value = Int(value)
            return
        }
        let stringValue = try container.decode(String.self)
        if let value = Int(stringValue) {
            self.value = value
        } else if let value = Double(stringValue) {
            self.value = Int(value)
        } else {
            self.value = 0
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleInt(forKey key: Key) throws -> Int {
        try decode(LisdoBackendFlexibleInt.self, forKey: key).value
    }
}
