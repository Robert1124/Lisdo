import Foundation

public enum TaskDraftProviderRetryClassification: Equatable, Sendable {
    case retryableTransient
    case nonRetryable
}

public protocol TaskDraftProviderRetryClassifying {
    var taskDraftRetryClassification: TaskDraftProviderRetryClassification { get }
}

public enum TaskDraftProviderOutputRetry {
    public static let defaultMaximumAttempts = 3

    public static func generateDraft(
        provider: any TaskDraftProvider,
        input: TaskDraftInput,
        categories: [Category],
        options: TaskDraftProviderOptions,
        maximumAttempts: Int = defaultMaximumAttempts,
        retryDelayNanoseconds: UInt64 = 180_000_000
    ) async throws -> ProcessingDraft {
        let attemptLimit = max(1, maximumAttempts)
        var attempt = 1

        while true {
            do {
                return try await provider.generateDraft(
                    input: input,
                    categories: categories,
                    options: options
                )
            } catch {
                guard isRetryableProviderError(error), attempt < attemptLimit else {
                    throw error
                }

                attempt += 1
                if retryDelayNanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt - 1) * retryDelayNanoseconds)
                }
            }
        }
    }

    public static func isRetryableProviderError(_ error: Error) -> Bool {
        if let classifyingError = error as? any TaskDraftProviderRetryClassifying {
            return classifyingError.taskDraftRetryClassification == .retryableTransient
        }

        if let urlError = error as? URLError {
            return isTransientURLErrorCode(urlError.code)
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return isTransientURLErrorCode(URLError.Code(rawValue: nsError.code))
        }

        if error is DraftParsingError {
            return true
        }

        return false
    }

    public static func isRetryableAIOutputError(_ error: Error) -> Bool {
        isRetryableProviderError(error)
    }

    public static func isTransientHTTPStatus(_ statusCode: Int) -> Bool {
        switch statusCode {
        case 408, 429, 500, 502, 503, 504:
            return true
        default:
            return false
        }
    }

    public static func isTransientURLErrorCode(_ code: URLError.Code) -> Bool {
        switch code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }
}

extension CLIProviderError: TaskDraftProviderRetryClassifying {
    public var taskDraftRetryClassification: TaskDraftProviderRetryClassification {
        switch self {
        case .timedOut, .invalidJSON:
            return .retryableTransient
        case .nonZeroExit:
            return .nonRetryable
        }
    }
}
