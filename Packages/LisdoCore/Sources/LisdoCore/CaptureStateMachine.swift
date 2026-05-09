import Foundation

public enum CaptureStatusTransitionError: Error, Equatable, Sendable {
    case invalidTransition(from: CaptureStatus, to: CaptureStatus)
}

public extension CaptureItem {
    func canTransition(to nextStatus: CaptureStatus) -> Bool {
        switch (status, nextStatus) {
        case (.rawCaptured, .pendingProcessing),
             (.pendingProcessing, .processing),
             (.processing, .processedDraft),
             (.processing, .failed),
             (.processedDraft, .approvedTodo),
             (.failed, .retryPending),
             (.retryPending, .processing):
            return true
        default:
            return false
        }
    }

    func transition(to nextStatus: CaptureStatus, error: String? = nil) throws {
        guard canTransition(to: nextStatus) else {
            throw CaptureStatusTransitionError.invalidTransition(from: status, to: nextStatus)
        }

        status = nextStatus

        switch nextStatus {
        case .failed:
            processingError = error
        case .retryPending, .processing, .processedDraft, .approvedTodo:
            processingError = nil
        case .rawCaptured, .pendingProcessing:
            break
        }
    }
}
