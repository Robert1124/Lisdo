import Foundation
import LisdoCore
import SwiftData
import UserNotifications

#if canImport(WidgetKit)
import WidgetKit
#endif

enum LisdoMacNotifications {
    static let openCapture = Notification.Name("LisdoMacOpenCapture")
    static let hotKeyStatusDefaultsKey = "lisdo.mac.global-hotkey.status"
}

private enum LisdoNotificationFeedback {
    static func postCaptureStatus(title: String, body: String, identifier: String = UUID().uuidString) async {
        let settings = await notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: "lisdo.capture-status.\(identifier)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }
}

private enum LisdoWidgetTimelineRefresh {
    static func request(reason: String) {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #else
        _ = reason
        #endif
    }
}

struct LisdoMacProcessingOutcome: Equatable {
    enum Kind: Equatable {
        case draftCreated
        case pendingSaved
        case failedSaved
        case skipped
    }

    var kind: Kind
    var message: String

    static func draftCreated(_ message: String) -> LisdoMacProcessingOutcome {
        LisdoMacProcessingOutcome(kind: .draftCreated, message: message)
    }

    static func pendingSaved(_ message: String) -> LisdoMacProcessingOutcome {
        LisdoMacProcessingOutcome(kind: .pendingSaved, message: message)
    }

    static func failedSaved(_ message: String) -> LisdoMacProcessingOutcome {
        LisdoMacProcessingOutcome(kind: .failedSaved, message: message)
    }

    static func skipped(_ message: String) -> LisdoMacProcessingOutcome {
        LisdoMacProcessingOutcome(kind: .skipped, message: message)
    }
}

@MainActor
enum LisdoMacMVP2Processing {
    static let preferenceStore = LisdoLocalProviderPreferenceStore()

    static var providerMode: ProviderMode {
        preferenceStore.readProviderMode(default: .openAICompatibleBYOK)
    }

    static var providerModeLabel: String {
        DraftProviderFactory.metadata(for: providerMode).displayName
    }

    static func macOnlyCLISettings() -> MacOnlyCLIProviderSettings? {
        guard let localSettings = preferenceStore.readMacOnlyCLISettings() else {
            return nil
        }

        return macOnlyCLISettings(from: localSettings)
    }

    nonisolated static func macOnlyCLISettings(from localSettings: MacOnlyCLILocalSettings) -> MacOnlyCLIProviderSettings {
        return MacOnlyCLIProviderSettings(
            descriptor: localSettings.descriptor,
            executablePath: localSettings.executablePath,
            timeoutSeconds: localSettings.descriptor.defaultTimeoutSeconds
        )
    }

    static func processExtractedCapture(
        sourceType: CaptureSourceType,
        sourceText: String? = nil,
        transcriptText: String? = nil,
        transcriptLanguage: String? = nil,
        sourceImageAssetId: String? = nil,
        sourceAudioAssetId: String? = nil,
        imageAttachment: TaskDraftImageAttachment? = nil,
        audioAttachment: TaskDraftAudioAttachment? = nil,
        userNote: String? = nil,
        selectedCategoryId: String,
        categories: [Category],
        modelContext: ModelContext
    ) async -> LisdoMacProcessingOutcome {
        let payload = LisdoCapturePayload(
            sourceType: sourceType,
            sourceText: sourceText,
            sourceImageAssetId: sourceImageAssetId,
            sourceAudioAssetId: sourceAudioAssetId,
            transcriptText: transcriptText,
            transcriptLanguage: transcriptLanguage,
            userNote: userNote,
            createdDevice: .mac
        )

        if (imageAttachment != nil || audioAttachment != nil), !supportsDirectAttachmentProvider(providerMode) {
            return saveFailedCaptureWithoutProvider(
                from: payload,
                providerMode: providerMode,
                message: "\(DraftProviderFactory.metadata(for: providerMode).displayName) does not support direct image/audio attachments in Lisdo yet. Switch this capture setting back to OCR/transcript or choose an OpenAI-compatible provider.",
                modelContext: modelContext
            )
        }

        guard let providerPlan = makeSelectedProviderPlan(mode: providerMode) else {
            return saveFailedCaptureWithoutProvider(
                from: payload,
                providerMode: providerMode,
                message: noProviderMessage(startingWith: providerMode),
                modelContext: modelContext
            )
        }

        return await createDraftFirstCapture(
            from: payload,
            providerPlan: providerPlan,
            providerMode: providerMode,
            imageAttachment: imageAttachment,
            audioAttachment: audioAttachment,
            selectedCategoryId: selectedCategoryId,
            categories: categories,
            modelContext: modelContext
        )
    }

    static func processQueuedCapture(
        _ capture: CaptureItem,
        selectedCategoryId: String,
        categories: [Category],
        modelContext: ModelContext
    ) async -> LisdoMacProcessingOutcome {
        guard isQueueProcessable(capture) else {
            return .skipped("Skipped a capture that is not pending or retry-ready.")
        }

        let startingMode = providerMode
        guard let providerPlan = makeSelectedProviderPlan(mode: startingMode) else {
            failCapture(capture, message: noProviderMessage(startingWith: startingMode))
            try? modelContext.save()
            publishCaptureChange(
                reason: "Mac queue item failed missing provider",
                notificationTitle: "Capture processing failed",
                notificationBody: noProviderMessage(startingWith: startingMode),
                identifier: capture.id.uuidString
            )
            return .failedSaved(noProviderMessage(startingWith: startingMode))
        }

        do {
            try leaseForProviderProcessing(capture)
            try modelContext.save()
            publishCaptureChange(reason: "Mac queue item processing")

            let sourceText = try capture.normalizedProcessableText()
            let draft = try await providerPlan.provider.generateDraft(
                input: TaskDraftInput(
                    captureItemId: capture.id,
                    sourceText: sourceText,
                    userNote: capture.userNote,
                    preferredSchemaPreset: categories.category(id: selectedCategoryId)?.schemaPreset,
                    captureCreatedAt: capture.createdAt,
                    timeZoneIdentifier: TimeZone.current.identifier
                ),
                categories: categories,
                options: TaskDraftProviderOptions(model: providerPlan.modelName)
            )
            draft.recommendedCategoryId = draft.recommendedCategoryId ?? selectedCategoryId
            try markProcessingSucceeded(capture, with: draft)
            modelContext.insert(draft)
            try modelContext.save()
            publishCaptureChange(
                reason: "Mac queue draft created",
                notificationTitle: "Draft ready",
                notificationBody: successMessage(for: providerPlan),
                identifier: capture.id.uuidString
            )
            return .draftCreated("Draft created from Mac queue. \(successMessage(for: providerPlan))")
        } catch let error as CLIProviderError {
            if capture.status == .processing {
                try? capture.markCLIProcessingFailed(error)
            } else {
                failCapture(capture, message: error.userReadableMessage)
            }
            try? modelContext.save()
            publishCaptureChange(
                reason: "Mac queue item failed",
                notificationTitle: "Capture processing failed",
                notificationBody: error.userReadableMessage,
                identifier: capture.id.uuidString
            )
            return .failedSaved(error.userReadableMessage)
        } catch {
            failCapture(capture, message: error.localizedDescription)
            try? modelContext.save()
            publishCaptureChange(
                reason: "Mac queue item failed",
                notificationTitle: "Capture processing failed",
                notificationBody: error.localizedDescription,
                identifier: capture.id.uuidString
            )
            return .failedSaved("Processing failed: \(error.localizedDescription)")
        }
    }

    static func processAllQueuedCaptures(
        _ captures: [CaptureItem],
        selectedCategoryId: String,
        categories: [Category],
        modelContext: ModelContext,
        onItemComplete: ((LisdoMacProcessingOutcome) -> Void)? = nil
    ) async -> LisdoMacProcessingOutcome {
        let queue = CaptureBatchSelector.processablePendingCaptures(from: captures)
        guard !queue.isEmpty else {
            return .skipped("No pending or retry-ready captures.")
        }

        var createdDrafts = 0
        var failedItems = 0

        for capture in queue {
            let outcome = await processQueuedCapture(
                capture,
                selectedCategoryId: selectedCategoryId,
                categories: categories,
                modelContext: modelContext
            )
            onItemComplete?(outcome)

            switch outcome.kind {
            case .draftCreated:
                createdDrafts += 1
            case .failedSaved:
                failedItems += 1
            case .pendingSaved, .skipped:
                break
            }
        }

        if failedItems > 0 {
            return .failedSaved("Processed \(queue.count) captures: \(createdDrafts) drafts, \(failedItems) failed.")
        }
        return .draftCreated("Processed \(queue.count) captures into \(createdDrafts) drafts for review.")
    }

    static func retryCapture(_ capture: CaptureItem, modelContext: ModelContext) -> LisdoMacProcessingOutcome {
        do {
            _ = try CaptureBatchActions.queueFailedCapturesForRetry([capture])
            try modelContext.save()
            publishCaptureChange(
                reason: "Mac capture retry queued",
                notificationTitle: "Retry queued",
                notificationBody: "The failed capture is ready for provider processing again.",
                identifier: capture.id.uuidString
            )
            return .pendingSaved("Capture queued for retry. Use Process All to run it on this Mac.")
        } catch {
            return .failedSaved("Could not queue retry: \(error.localizedDescription)")
        }
    }

    static func pendingQueue(from captures: [CaptureItem]) -> [CaptureItem] {
        captures.filter { capture in
            capture.createdDevice == .iPhone
            || capture.status == .pendingProcessing
            || capture.status == .processing
            || capture.status == .failed
            || capture.status == .retryPending
        }
    }

    static func reviseDraft(
        _ draft: ProcessingDraft,
        capture: CaptureItem?,
        revisionInstructions: String,
        selectedCategoryId: String,
        categories: [Category],
        modelContext: ModelContext
    ) async -> LisdoMacProcessingOutcome {
        let trimmedInstructions = revisionInstructions.lisdoTrimmed
        guard !trimmedInstructions.isEmpty else {
            return .skipped("Enter revision instructions before rerunning the draft.")
        }

        guard let sourceText = revisionSourceText(draft: draft, capture: capture) else {
            return .failedSaved("Original source text is unavailable, so Lisdo cannot rerun this draft.")
        }

        guard let providerPlan = makeSelectedProviderPlan(mode: providerMode) else {
            return .failedSaved(noProviderMessage(startingWith: providerMode))
        }

        do {
            let revised = try await providerPlan.provider.generateDraft(
                input: TaskDraftInput(
                    captureItemId: draft.captureItemId,
                    sourceText: sourceText,
                    userNote: capture?.userNote,
                    preferredSchemaPreset: categories.category(id: selectedCategoryId)?.schemaPreset,
                    revisionInstructions: trimmedInstructions,
                    captureCreatedAt: capture?.createdAt ?? draft.dateResolutionReferenceDate,
                    timeZoneIdentifier: TimeZone.current.identifier
                ),
                categories: categories,
                options: TaskDraftProviderOptions(model: providerPlan.modelName)
            )

            draft.recommendedCategoryId = revised.recommendedCategoryId ?? selectedCategoryId
            draft.title = revised.title
            draft.summary = revised.summary
            draft.blocks = revised.blocks
            draft.suggestedReminders = revised.suggestedReminders
            draft.confidence = revised.confidence
            draft.generatedByProvider = revised.generatedByProvider
            draft.generatedAt = Date()
            draft.needsClarification = revised.needsClarification
            draft.questionsForUser = revised.questionsForUser
            draft.dueDateText = revised.dueDateText
            draft.dueDate = revised.dueDate
            draft.scheduledDate = revised.scheduledDate
            draft.dateResolutionReferenceDate = revised.dateResolutionReferenceDate
            draft.priority = revised.priority
            try modelContext.save()
            publishCaptureChange(reason: "Mac draft revised")
            return .draftCreated("Draft revised. Review it before saving a todo.")
        } catch {
            return .failedSaved("Revision failed: \(error.localizedDescription)")
        }
    }

    private static func createDraftFirstCapture(
        from payload: LisdoCapturePayload,
        providerPlan: ProviderPlan,
        providerMode: ProviderMode,
        imageAttachment: TaskDraftImageAttachment?,
        audioAttachment: TaskDraftAudioAttachment?,
        selectedCategoryId: String,
        categories: [Category],
        modelContext: ModelContext
    ) async -> LisdoMacProcessingOutcome {
        let capture: CaptureItem
        do {
            capture = try LisdoCaptureFactory.makeDirectProviderCapture(
                from: payload,
                providerMode: providerMode
            )
        } catch {
            let failed = LisdoCaptureFactory.makeFailedCapture(
                from: payload,
                providerMode: providerMode,
                reason: .emptyContent
            )
            modelContext.insert(failed)
            try? modelContext.save()
            publishCaptureChange(
                reason: "Mac direct capture failed empty content",
                notificationTitle: "Capture needs attention",
                notificationBody: "Lisdo could not find processable text in this capture.",
                identifier: failed.id.uuidString
            )
            return .failedSaved("Capture did not contain processable text.")
        }

        do {
            modelContext.insert(capture)
            try capture.transition(to: .pendingProcessing)
            try capture.transition(to: .processing)
            try modelContext.save()
            publishCaptureChange(reason: "Mac direct capture processing")

            let draft = try await providerPlan.provider.generateDraft(
                input: TaskDraftInput(
                    captureItemId: capture.id,
                    sourceText: try capture.normalizedProcessableText(),
                    userNote: capture.userNote,
                    preferredSchemaPreset: categories.category(id: selectedCategoryId)?.schemaPreset,
                    captureCreatedAt: capture.createdAt,
                    timeZoneIdentifier: TimeZone.current.identifier,
                    imageAttachment: imageAttachment,
                    audioAttachment: audioAttachment
                ),
                categories: categories,
                options: TaskDraftProviderOptions(model: providerPlan.modelName)
            )
            draft.recommendedCategoryId = draft.recommendedCategoryId ?? selectedCategoryId
            try capture.transition(to: .processedDraft)
            modelContext.insert(draft)
            try modelContext.save()
            publishCaptureChange(
                reason: "Mac direct draft created",
                notificationTitle: "Draft ready",
                notificationBody: successMessage(for: providerPlan),
                identifier: capture.id.uuidString
            )
            return .draftCreated("Draft created. Review it in Inbox before saving a todo. \(successMessage(for: providerPlan))")
        } catch let error as CLIProviderError {
            if capture.status == .processing {
                try? capture.markCLIProcessingFailed(error)
            } else {
                failCapture(capture, message: error.userReadableMessage)
            }
            try? modelContext.save()
            publishCaptureChange(
                reason: "Mac direct capture failed",
                notificationTitle: "Capture processing failed",
                notificationBody: error.userReadableMessage,
                identifier: capture.id.uuidString
            )
            return .failedSaved(error.userReadableMessage)
        } catch {
            failCapture(capture, message: error.localizedDescription)
            try? modelContext.save()
            publishCaptureChange(
                reason: "Mac direct capture failed",
                notificationTitle: "Capture processing failed",
                notificationBody: error.localizedDescription,
                identifier: capture.id.uuidString
            )
            return .failedSaved("Provider failed before a draft was created: \(error.localizedDescription)")
        }
    }

    private static func saveFailedCaptureWithoutProvider(
        from payload: LisdoCapturePayload,
        providerMode: ProviderMode,
        message: String,
        modelContext: ModelContext
    ) -> LisdoMacProcessingOutcome {
        do {
            let capture = CaptureItem(
                sourceType: payload.sourceType,
                sourceText: payload.sourceText?.lisdoTrimmed.nilIfEmpty,
                sourceImageAssetId: payload.sourceImageAssetId?.lisdoTrimmed.nilIfEmpty,
                sourceAudioAssetId: payload.sourceAudioAssetId?.lisdoTrimmed.nilIfEmpty,
                transcriptText: payload.transcriptText?.lisdoTrimmed.nilIfEmpty,
                transcriptLanguage: payload.transcriptLanguage?.lisdoTrimmed.nilIfEmpty,
                userNote: payload.userNote?.lisdoTrimmed.nilIfEmpty,
                createdDevice: payload.createdDevice,
                createdAt: payload.createdAt,
                status: .failed,
                preferredProviderMode: providerMode,
                processingError: message
            )
            _ = try capture.normalizedProcessableText()
            modelContext.insert(capture)
            try modelContext.save()
            publishCaptureChange(
                reason: "Mac capture failed provider settings",
                notificationTitle: "Capture processing failed",
                notificationBody: message,
                identifier: capture.id.uuidString
            )
            return .failedSaved(message)
        } catch {
            let capture = LisdoCaptureFactory.makeFailedCapture(
                from: payload,
                providerMode: providerMode,
                reason: .emptyContent
            )
            modelContext.insert(capture)
            try? modelContext.save()
            publishCaptureChange(
                reason: "Mac capture failed empty content",
                notificationTitle: "Capture needs attention",
                notificationBody: "Lisdo could not find processable text in this capture.",
                identifier: capture.id.uuidString
            )
            return .failedSaved("Capture did not contain processable text.")
        }
    }

    private struct ProviderPlan {
        var provider: any TaskDraftProvider
        var modelName: String
    }

    private static func makeSelectedProviderPlan(mode: ProviderMode) -> ProviderPlan? {
        let factory = DraftProviderFactory(
            preferenceStore: preferenceStore,
            macOnlyCLIProviderBuilder: { localSettings in
                MacOnlyCLIDraftProvider(settings: macOnlyCLISettings(from: localSettings))
            }
        )

        guard let provider = try? factory.makeProvider(for: mode) else {
            return nil
        }

        let settings = factory.loadSettings(for: mode)
        return ProviderPlan(
            provider: provider,
            modelName: settings.model
        )
    }

    private static func noProviderMessage(startingWith mode: ProviderMode) -> String {
        let name = DraftProviderFactory.metadata(for: mode).displayName
        return "\(name) is not configured or cannot be used on this device. Configure this selected provider in Provider Settings, then retry."
    }

    private static func successMessage(for plan: ProviderPlan) -> String {
        return "Used \(plan.provider.displayName)."
    }

    private static func supportsDirectAttachmentProvider(_ mode: ProviderMode) -> Bool {
        switch mode {
        case .openAICompatibleBYOK, .minimax, .openRouter, .ollama, .lmStudio, .localModel:
            return true
        case .anthropic, .gemini, .macOnlyCLI:
            return false
        }
    }

    private static func isQueueProcessable(_ capture: CaptureItem) -> Bool {
        CaptureBatchSelector.processablePendingCaptures(from: [capture]).contains { $0.id == capture.id }
            || (capture.status == .processing && capture.processingLockCreatedAt == nil)
    }

    private static func leaseForProviderProcessing(_ capture: CaptureItem) throws {
        switch capture.status {
        case .pendingProcessing, .retryPending:
            try capture.transition(to: .processing)
        case .processing:
            break
        case .rawCaptured, .processedDraft, .approvedTodo, .failed:
            throw CaptureMacProcessingError.notProcessable(status: capture.status)
        }

        capture.assignedProcessorDeviceId = processorDeviceId
        capture.processingLockDeviceId = processorDeviceId
        capture.processingLockCreatedAt = Date()
        capture.processingError = nil
    }

    private static func markProcessingSucceeded(_ capture: CaptureItem, with draft: ProcessingDraft) throws {
        guard draft.captureItemId == capture.id else {
            throw CaptureMacProcessingError.draftCaptureMismatch(expected: capture.id, actual: draft.captureItemId)
        }

        try capture.transition(to: .processedDraft)
        capture.processingLockDeviceId = nil
        capture.processingLockCreatedAt = nil
        capture.processingError = nil
    }

    private static func revisionSourceText(draft: ProcessingDraft, capture: CaptureItem?) -> String? {
        if let capture, let text = try? capture.normalizedProcessableText() {
            return text
        }

        let draftText = [
            Optional(draft.title),
            draft.summary,
            Optional(draft.blocks.sorted { $0.order < $1.order }.map(\.content).joined(separator: "\n"))
        ]
        .compactMap { $0?.lisdoTrimmed.nilIfEmpty }
        .joined(separator: "\n\n")

        return draftText.lisdoTrimmed.nilIfEmpty
    }

    private static func failCapture(_ capture: CaptureItem, message: String) {
        switch capture.status {
        case .rawCaptured:
            try? capture.transition(to: .pendingProcessing)
            try? capture.transition(to: .processing)
            try? capture.transition(to: .failed, error: message)
        case .pendingProcessing:
            try? capture.transition(to: .processing)
            try? capture.transition(to: .failed, error: message)
        case .retryPending:
            try? capture.transition(to: .processing)
            try? capture.transition(to: .failed, error: message)
        case .processing:
            try? capture.transition(to: .failed, error: message)
        case .failed:
            capture.processingError = message
        case .processedDraft, .approvedTodo:
            break
        }

        capture.processingLockDeviceId = nil
        capture.processingLockCreatedAt = nil
    }

    private static func publishCaptureChange(
        reason: String,
        notificationTitle: String? = nil,
        notificationBody: String? = nil,
        identifier: String = UUID().uuidString
    ) {
        LisdoWidgetTimelineRefresh.request(reason: reason)

        guard let notificationTitle, let notificationBody else { return }
        Task {
            await LisdoNotificationFeedback.postCaptureStatus(
                title: notificationTitle,
                body: notificationBody,
                identifier: identifier
            )
        }
    }

    private static var processorDeviceId: String {
        let hostName = ProcessInfo.processInfo.hostName.lisdoTrimmed
        if !hostName.isEmpty {
            return "mac:\(hostName)"
        }
        return "mac:\(UUID().uuidString)"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
