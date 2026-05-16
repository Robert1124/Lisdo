import Foundation
import LisdoCore
import SwiftData
import UIKit

@MainActor
@available(iOSApplicationExtension, unavailable)
final class LisdoHostedPendingQueueProcessor {
    static let queueDidChangeNotification = Notification.Name("LisdoHostedPendingQueueDidChange")

    private let modelContext: ModelContext
    private let providerFactory: DraftProviderFactory
    private let textRecognitionService: VisionTextRecognitionService
    private let processorDeviceId: String
    private let staleLockInterval: TimeInterval
    private var isProcessing = false
    private var shouldRunAnotherPass = false

    init(
        modelContext: ModelContext,
        providerFactory: DraftProviderFactory = DraftProviderFactory(),
        textRecognitionService: VisionTextRecognitionService = VisionTextRecognitionService(),
        processorDeviceId: String? = nil,
        staleLockInterval: TimeInterval = 15 * 60
    ) {
        self.modelContext = modelContext
        self.providerFactory = providerFactory
        self.textRecognitionService = textRecognitionService
        self.processorDeviceId = processorDeviceId
            ?? UIDevice.current.identifierForVendor?.uuidString
            ?? "lisdo-ios-hosted-processor"
        self.staleLockInterval = staleLockInterval
    }

    static func requestProcessing() {
        NotificationCenter.default.post(name: queueDidChangeNotification, object: nil)
    }

    func processPendingHostedCaptures(categories: [Category]) async {
        guard !isProcessing else {
            shouldRunAnotherPass = true
            return
        }
        isProcessing = true
        defer { isProcessing = false }

        let fallbackCategoryId = categories.first { $0.id == DefaultCategorySeeder.inboxCategoryId }?.id
            ?? categories.first?.id
            ?? DefaultCategorySeeder.inboxCategoryId

        repeat {
            shouldRunAnotherPass = false
            while let capture = nextPendingHostedCapture() {
                await process(capture, categories: categories, fallbackCategoryId: fallbackCategoryId)
            }
        } while shouldRunAnotherPass
    }

    private func nextPendingHostedCapture(now: Date = Date()) -> CaptureItem? {
        let descriptor = FetchDescriptor<CaptureItem>(
            sortBy: [SortDescriptor(\CaptureItem.createdAt, order: .forward)]
        )
        let captures = (try? modelContext.fetch(descriptor)) ?? []
        return captures.first {
            $0.createdDevice == .iPhone
                && $0.isHostedProcessablePending(now: now, staleLockInterval: staleLockInterval)
        }
    }

    private func process(
        _ capture: CaptureItem,
        categories: [Category],
        fallbackCategoryId: String
    ) async {
        do {
            try capture.leaseForHostedProcessing(
                processorDeviceId: processorDeviceId,
                now: Date(),
                staleLockInterval: staleLockInterval
            )
            try modelContext.save()
            LisdoWidgetTimelineRefresh.request(reason: "iOS hosted queue item processing")

            let providerMode = capture.preferredProviderMode
            guard let provider = try providerFactory.makeProvider(for: providerMode) else {
                throw LisdoHostedPendingQueueError.providerUnavailable(providerMode)
            }

            let settings = providerFactory.loadSettings(for: providerMode)
            if hasPendingAttachments(for: capture),
               !HostedProviderQueuePolicy.supportsDirectAttachments(providerMode) {
                throw LisdoHostedPendingQueueError.unsupportedDirectAttachmentProvider(providerMode)
            }
            let attachments = pendingAttachmentContext(for: capture, providerMode: providerMode)
            let sourceText = pendingSourceText(for: capture, attachmentContext: attachments)
            let pipeline = LisdoDraftPipeline(
                provider: provider,
                textRecognitionService: textRecognitionService,
                deviceType: .iPhone
            )

            let result = try await LisdoBackgroundTaskRunner.run(named: "Lisdo hosted pending draft") {
                try await pipeline.processPendingCapture(
                    capture,
                    categories: categories,
                    sourceTextOverride: sourceText,
                    imageAttachment: attachments.imageAttachment,
                    audioAttachment: attachments.audioAttachment,
                    preferredSchemaPreset: categories.first { $0.id == fallbackCategoryId }?.schemaPreset,
                    options: TaskDraftProviderOptions(model: settings.model)
                )
            }

            guard let currentCapture = fetchCapture(id: capture.id) else {
                return
            }

            result.draft.recommendedCategoryId = result.draft.recommendedCategoryId ?? fallbackCategoryId
            try markHostedProcessingSucceeded(currentCapture, draft: result.draft)
            modelContext.insert(result.draft)
            deletePendingAttachments(for: currentCapture)
            try modelContext.save()
            LisdoWidgetTimelineRefresh.request(reason: "iOS hosted queue draft created")
            await LisdoNotificationFeedback.postCaptureStatus(
                title: "Draft ready",
                body: "Lisdo processed a capture into a draft for review.",
                identifier: currentCapture.id.uuidString
            )
        } catch {
            guard let currentCapture = fetchCapture(id: capture.id) else {
                return
            }

            if error.isLisdoQueueCancellation {
                markHostedProcessingRetryPending(currentCapture)
                try? modelContext.save()
                LisdoWidgetTimelineRefresh.request(reason: "iOS hosted queue item paused")
                return
            }

            let message = error.lisdoHostedQueueUserMessage
            markHostedProcessingFailed(currentCapture, message: message)
            try? modelContext.save()
            LisdoWidgetTimelineRefresh.request(reason: "iOS hosted queue item failed")
        }
    }

    private func fetchCapture(id: UUID) -> CaptureItem? {
        let requestedId = id
        var descriptor = FetchDescriptor<CaptureItem>(
            predicate: #Predicate { capture in
                capture.id == requestedId
            }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func markHostedProcessingSucceeded(
        _ capture: CaptureItem,
        draft: ProcessingDraft
    ) throws {
        if capture.status == .processing {
            _ = try capture.markHostedProcessingSucceeded(with: draft)
            return
        }

        guard capture.status == .processedDraft else {
            _ = try capture.markHostedProcessingSucceeded(with: draft)
            return
        }

        capture.processingLockDeviceId = nil
        capture.processingLockCreatedAt = nil
        capture.processingError = nil
    }

    private func markHostedProcessingFailed(
        _ capture: CaptureItem,
        message: String
    ) {
        if capture.status == .processing {
            try? capture.markHostedProcessingFailed(message)
        } else {
            capture.processingError = message
        }

        capture.processingLockDeviceId = nil
        capture.processingLockCreatedAt = nil
    }

    private func markHostedProcessingRetryPending(_ capture: CaptureItem) {
        if capture.status == .processing {
            try? capture.markHostedProcessingFailed("Processing paused. Ready to retry.")
        }
        if capture.status == .failed {
            try? capture.queueForRetry()
        }

        capture.processingLockDeviceId = nil
        capture.processingLockCreatedAt = nil
    }

    private func pendingAttachmentContext(
        for capture: CaptureItem,
        providerMode: ProviderMode
    ) -> HostedPendingAttachmentContext {
        guard HostedProviderQueuePolicy.supportsDirectAttachments(providerMode) else {
            return HostedPendingAttachmentContext()
        }

        let attachments = (try? LisdoPendingAttachmentStore(context: modelContext).fetchAttachments(forCaptureItemId: capture.id)) ?? []
        guard !attachments.isEmpty else {
            return HostedPendingAttachmentContext()
        }

        let imageAttachments = attachments.filter { $0.kind == .image }
        let audioAttachments = attachments.filter { $0.kind == .audio }
        let summary = attachments.enumerated().map { index, attachment in
            let filename = attachment.filename?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfLisdoQueueEmpty ?? "unnamed"
            return "\(index + 1). \(attachment.kind.rawValue) attachment: \(filename), \(attachment.mimeOrFormat), \(attachment.data.count) bytes"
        }
        .joined(separator: "\n")
        .nilIfLisdoQueueEmpty

        return HostedPendingAttachmentContext(
            imageAttachment: imageAttachments.first.map {
                TaskDraftImageAttachment(data: $0.data, mimeType: $0.mimeOrFormat, filename: $0.filename)
            },
            audioAttachment: audioAttachments.first.map {
                TaskDraftAudioAttachment(data: $0.data, format: $0.mimeOrFormat, filename: $0.filename)
            },
            attachmentSummary: summary
        )
    }

    private func hasPendingAttachments(for capture: CaptureItem) -> Bool {
        let attachments = (try? LisdoPendingAttachmentStore(context: modelContext).fetchAttachments(forCaptureItemId: capture.id)) ?? []
        return !attachments.isEmpty
    }

    private func pendingSourceText(
        for capture: CaptureItem,
        attachmentContext: HostedPendingAttachmentContext
    ) -> String? {
        let baseText = (try? capture.normalizedProcessableText())?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfLisdoQueueEmpty
        let attachmentText = attachmentContext.attachmentSummary.map {
            "Original local media included for direct provider analysis:\n\($0)"
        }

        return [
            baseText,
            attachmentText
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .nilIfLisdoQueueEmpty
    }

    private func deletePendingAttachments(for capture: CaptureItem) {
        try? LisdoPendingAttachmentStore(context: modelContext).deleteAttachments(forCaptureItemId: capture.id)
    }
}

private struct HostedPendingAttachmentContext {
    var imageAttachment: TaskDraftImageAttachment?
    var audioAttachment: TaskDraftAudioAttachment?
    var attachmentSummary: String?
}

private enum LisdoHostedPendingQueueError: LocalizedError {
    case providerUnavailable(ProviderMode)
    case unsupportedDirectAttachmentProvider(ProviderMode)

    var errorDescription: String? {
        switch self {
        case .providerUnavailable(let mode):
            return "\(DraftProviderFactory.metadata(for: mode).displayName) is not configured on this iPhone. Configure the provider, then retry the capture."
        case .unsupportedDirectAttachmentProvider(let mode):
            return "\(DraftProviderFactory.metadata(for: mode).displayName) does not support direct media attachments in Lisdo yet. Switch image capture back to OCR or choose an OpenAI-compatible provider."
        }
    }
}

private extension Error {
    var isLisdoQueueCancellation: Bool {
        if self is CancellationError {
            return true
        }

        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    var lisdoHostedQueueUserMessage: String {
        if let localizedError = self as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        let description = localizedDescription
        return description.isEmpty ? String(describing: self) : description
    }
}

private extension String {
    var nilIfLisdoQueueEmpty: String? {
        isEmpty ? nil : self
    }
}
