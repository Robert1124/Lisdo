import Foundation

public enum TaskDraftProviderAttemptOutcome: String, Codable, Equatable, Sendable {
    case success
    case failure
}

public struct TaskDraftProviderAttempt: Codable, Equatable, Sendable {
    public var providerId: String
    public var displayName: String
    public var mode: ProviderMode
    public var outcome: TaskDraftProviderAttemptOutcome
    public var errorDescription: String?

    public init(
        providerId: String,
        displayName: String,
        mode: ProviderMode,
        outcome: TaskDraftProviderAttemptOutcome,
        errorDescription: String? = nil
    ) {
        self.providerId = providerId
        self.displayName = displayName
        self.mode = mode
        self.outcome = outcome
        self.errorDescription = errorDescription
    }
}

public struct TaskDraftFallbackError: Error, Equatable, Sendable {
    public var attemptedProviderIds: [String]
    public var attempts: [TaskDraftProviderAttempt]

    public init(attemptedProviderIds: [String], attempts: [TaskDraftProviderAttempt]) {
        self.attemptedProviderIds = attemptedProviderIds
        self.attempts = attempts
    }
}

extension TaskDraftFallbackError: LocalizedError {
    public var errorDescription: String? {
        if attemptedProviderIds.isEmpty {
            return "No draft providers were configured for fallback."
        }
        return "All draft providers failed: \(attemptedProviderIds.joined(separator: ", "))."
    }
}

public final class TaskDraftFallbackProvider: TaskDraftProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String
    public let mode: ProviderMode

    private let providers: [any TaskDraftProvider]
    private let lock = NSLock()
    private var attemptsStorage: [TaskDraftProviderAttempt] = []

    public var lastAttempts: [TaskDraftProviderAttempt] {
        lock.lock()
        defer { lock.unlock() }
        return attemptsStorage
    }

    public init(
        id: String = "provider-fallback",
        displayName: String = "Provider Fallback",
        mode: ProviderMode? = nil,
        providers: [any TaskDraftProvider]
    ) {
        self.id = id
        self.displayName = displayName
        self.mode = mode ?? providers.first?.mode ?? .openAICompatibleBYOK
        self.providers = providers
    }

    public func generateDraft(
        input: TaskDraftInput,
        categories: [Category],
        options: TaskDraftProviderOptions
    ) async throws -> ProcessingDraft {
        var attempts: [TaskDraftProviderAttempt] = []

        for provider in providers {
            do {
                let draft = try await provider.generateDraft(input: input, categories: categories, options: options)
                attempts.append(
                    TaskDraftProviderAttempt(
                        providerId: provider.id,
                        displayName: provider.displayName,
                        mode: provider.mode,
                        outcome: .success
                    )
                )
                updateLastAttempts(attempts)
                return draft
            } catch {
                attempts.append(
                    TaskDraftProviderAttempt(
                        providerId: provider.id,
                        displayName: provider.displayName,
                        mode: provider.mode,
                        outcome: .failure,
                        errorDescription: String(describing: error)
                    )
                )
            }
        }

        updateLastAttempts(attempts)
        throw TaskDraftFallbackError(
            attemptedProviderIds: attempts.map(\.providerId),
            attempts: attempts
        )
    }

    private func updateLastAttempts(_ attempts: [TaskDraftProviderAttempt]) {
        lock.lock()
        attemptsStorage = attempts
        lock.unlock()
    }
}
