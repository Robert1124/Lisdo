import Foundation

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
                guard isRetryableAIOutputError(error), attempt < attemptLimit else {
                    throw error
                }

                attempt += 1
                if retryDelayNanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt - 1) * retryDelayNanoseconds)
                }
            }
        }
    }

    public static func isRetryableAIOutputError(_ error: Error) -> Bool {
        if error is DraftParsingError {
            return true
        }

        if let cliError = error as? CLIProviderError {
            if case .invalidJSON = cliError {
                return true
            }
        }

        return false
    }
}
