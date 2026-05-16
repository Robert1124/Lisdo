import Foundation
import LisdoCore

public enum LisdoManagedDraftProviderError: Error, Equatable, Sendable {
    case invalidHTTPResponse
    case httpStatus(Int)
    case missingDraftJSON
}

extension LisdoManagedDraftProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "Lisdo did not receive a valid server response. Try again."
        case .httpStatus(402):
            return "Lisdo quota is not available for this account. Refresh Lisdo or choose a plan with included usage."
        case .httpStatus(let statusCode):
            return "Lisdo server returned HTTP \(statusCode)."
        case .missingDraftJSON:
            return "Lisdo returned an empty draft response. Try again."
        }
    }
}

extension LisdoManagedDraftProviderError: TaskDraftProviderRetryClassifying {
    public var taskDraftRetryClassification: TaskDraftProviderRetryClassification {
        switch self {
        case .httpStatus(let statusCode):
            return TaskDraftProviderOutputRetry.isTransientHTTPStatus(statusCode) ? .retryableTransient : .nonRetryable
        case .invalidHTTPResponse, .missingDraftJSON:
            return .retryableTransient
        }
    }
}

public final class LisdoManagedDraftProvider: TaskDraftProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String
    public let mode: ProviderMode = .lisdoManaged
    public let baseURL: URL
    public let model: String

    private let requestBuilder: any OpenAICompatibleDraftRequestBuilding
    private let backendClient: LisdoBackendClient

    public init(
        baseURL: URL,
        bearerToken: String,
        model: String,
        id: String = "lisdo-managed",
        displayName: String = "Lisdo",
        urlSession: URLSession = .shared,
        requestBuilder: any OpenAICompatibleDraftRequestBuilding = OpenAICompatibleDraftRequestBuilder()
    ) {
        self.baseURL = baseURL
        self.model = model
        self.id = id
        self.displayName = displayName
        self.requestBuilder = requestBuilder
        self.backendClient = LisdoBackendClient(baseURL: baseURL, bearerToken: bearerToken, urlSession: urlSession)
    }

    public func generateDraft(
        input: TaskDraftInput,
        categories: [Category],
        options: TaskDraftProviderOptions
    ) async throws -> ProcessingDraft {
        let effectiveOptions = TaskDraftProviderOptions(
            model: model,
            temperature: options.temperature,
            maximumOutputTokens: options.maximumOutputTokens
        )
        let chatRequest = requestBuilder.makeRequest(
            input: input,
            categories: categories,
            options: effectiveOptions
        )
        let payload = try await backendClient.generateDraft(chatRequest: chatRequest)
        postQuotaUpdate(payload.quota)

        let draftJSON = payload.draftJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draftJSON.isEmpty else {
            throw LisdoManagedDraftProviderError.missingDraftJSON
        }

        return try TaskDraftParser.parse(
            draftJSON,
            captureItemId: input.captureItemId,
            generatedByProvider: "\(id):\(model)"
        )
    }

    private func postQuotaUpdate(_ quota: LisdoBackendQuota) {
        NotificationCenter.default.post(
            name: .lisdoManagedQuotaDidUpdate,
            object: LisdoManagedQuotaUpdate(quota: quota, receivedAt: Date())
        )
    }
}

public struct LisdoManagedQuotaUpdate: Equatable, Sendable {
    public var quota: LisdoBackendQuota
    public var snapshot: LisdoEntitlementSnapshot
    public var receivedAt: Date

    public init(quota: LisdoBackendQuota, receivedAt: Date = Date()) {
        self.quota = quota
        self.snapshot = quota.entitlementSnapshot()
        self.receivedAt = receivedAt
    }
}

public extension Notification.Name {
    static let lisdoManagedQuotaDidUpdate = Notification.Name("com.yiwenwu.Lisdo.managedQuotaDidUpdate")
}
