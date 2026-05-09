import Foundation

public enum CaptureContentNormalizationError: Error, Equatable, Sendable {
    case emptyContent
}

public enum CaptureMacProcessingError: Error, Equatable, Sendable {
    case notMacOnlyCLI
    case notProcessable(status: CaptureStatus)
    case draftCaptureMismatch(expected: UUID, actual: UUID)
}

public enum CaptureTextNormalizer {
    public static func normalizedText(
        sourceType: CaptureSourceType,
        sourceText: String?,
        transcriptText: String?
    ) throws -> String {
        let trimmedTranscript = transcriptText?.trimmedNonEmpty
        let trimmedSource = sourceText?.trimmedNonEmpty

        let selectedText: String?
        switch sourceType {
        case .voiceNote:
            selectedText = trimmedTranscript ?? trimmedSource
        default:
            selectedText = trimmedTranscript ?? trimmedSource
        }

        guard let selectedText else {
            throw CaptureContentNormalizationError.emptyContent
        }
        return selectedText
    }
}

public extension CaptureItem {
    func normalizedProcessableText() throws -> String {
        try CaptureTextNormalizer.normalizedText(
            sourceType: sourceType,
            sourceText: sourceText,
            transcriptText: transcriptText
        )
    }

    func isMacProcessablePending(
        now: Date = Date(),
        staleLockInterval: TimeInterval = 900
    ) -> Bool {
        guard preferredProviderMode == .macOnlyCLI else {
            return false
        }

        switch status {
        case .pendingProcessing, .retryPending:
            return true
        case .processing:
            return isProcessingLockStale(now: now, staleLockInterval: staleLockInterval)
        case .rawCaptured, .processedDraft, .approvedTodo, .failed:
            return false
        }
    }

    func leaseForMacProcessing(
        processorDeviceId: String,
        now: Date = Date(),
        staleLockInterval: TimeInterval = 900
    ) throws {
        guard preferredProviderMode == .macOnlyCLI else {
            throw CaptureMacProcessingError.notMacOnlyCLI
        }

        switch status {
        case .pendingProcessing, .retryPending:
            try transition(to: .processing)
        case .processing:
            guard isProcessingLockStale(now: now, staleLockInterval: staleLockInterval) else {
                throw CaptureMacProcessingError.notProcessable(status: status)
            }
        case .rawCaptured, .processedDraft, .approvedTodo, .failed:
            throw CaptureMacProcessingError.notProcessable(status: status)
        }

        assignedProcessorDeviceId = processorDeviceId
        processingLockDeviceId = processorDeviceId
        processingLockCreatedAt = now
        processingError = nil
    }

    @discardableResult
    func markCLIProcessingSucceeded(with draft: ProcessingDraft) throws -> ProcessingDraft {
        guard draft.captureItemId == id else {
            throw CaptureMacProcessingError.draftCaptureMismatch(expected: id, actual: draft.captureItemId)
        }

        try transition(to: .processedDraft)
        processingLockDeviceId = nil
        processingLockCreatedAt = nil
        processingError = nil
        return draft
    }

    func markCLIProcessingFailed(_ error: CLIProviderError) throws {
        try transition(to: .failed, error: error.userReadableMessage)
        processingLockDeviceId = nil
        processingLockCreatedAt = nil
    }

    func queueForRetry() throws {
        try transition(to: .retryPending)
        processingLockDeviceId = nil
        processingLockCreatedAt = nil
    }

    private func isProcessingLockStale(now: Date, staleLockInterval: TimeInterval) -> Bool {
        guard let processingLockCreatedAt else {
            return true
        }
        return now.timeIntervalSince(processingLockCreatedAt) >= staleLockInterval
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
