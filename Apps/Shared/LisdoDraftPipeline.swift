import Foundation
import LisdoCore

public struct LisdoDraftPipelineResult {
    public var captureItem: CaptureItem
    public var draft: ProcessingDraft

    public init(captureItem: CaptureItem, draft: ProcessingDraft) {
        self.captureItem = captureItem
        self.draft = draft
    }
}

public enum LisdoDraftPipelineError: Error, Equatable, LocalizedError, Sendable {
    case emptySourceText
    case emptyRecognizedText
    case unsupportedDirectAttachmentProvider(ProviderMode)

    public var errorDescription: String? {
        switch self {
        case .emptySourceText:
            return "Capture did not contain processable text."
        case .emptyRecognizedText:
            return "No OCR text was found."
        case .unsupportedDirectAttachmentProvider(let mode):
            return "\(mode.rawValue) does not support direct image/audio attachments in Lisdo yet. Use OCR/transcript mode or choose an OpenAI-compatible provider."
        }
    }
}

public final class LisdoDraftPipeline: @unchecked Sendable {
    private let provider: any TaskDraftProvider
    private let textRecognitionService: any TextRecognitionService
    private let deviceType: DeviceType

    public init(
        provider: any TaskDraftProvider,
        textRecognitionService: any TextRecognitionService,
        deviceType: DeviceType
    ) {
        self.provider = provider
        self.textRecognitionService = textRecognitionService
        self.deviceType = deviceType
    }

    public func processTextCapture(
        _ sourceText: String,
        categories: [Category],
        userNote: String? = nil,
        preferredSchemaPreset: CategorySchemaPreset? = nil,
        revisionInstructions: String? = nil,
        options: TaskDraftProviderOptions
    ) async throws -> LisdoDraftPipelineResult {
        let trimmedText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw LisdoDraftPipelineError.emptySourceText
        }

        let captureItem = CaptureItem(
            sourceType: .textPaste,
            sourceText: trimmedText,
            userNote: userNote,
            createdDevice: deviceType,
            status: .rawCaptured,
            preferredProviderMode: provider.mode
        )

        return try await process(
            captureItem: captureItem,
            sourceText: trimmedText,
            categories: categories,
            preferredSchemaPreset: preferredSchemaPreset,
            revisionInstructions: revisionInstructions,
            options: options
        )
    }

    public func draftFromTextCapture(
        _ sourceText: String,
        categories: [Category],
        userNote: String? = nil,
        preferredSchemaPreset: CategorySchemaPreset? = nil,
        revisionInstructions: String? = nil,
        options: TaskDraftProviderOptions
    ) async throws -> ProcessingDraft {
        try await processTextCapture(
            sourceText,
            categories: categories,
            userNote: userNote,
            preferredSchemaPreset: preferredSchemaPreset,
            revisionInstructions: revisionInstructions,
            options: options
        ).draft
    }

    public func processExtractedCapture(
        sourceType: CaptureSourceType,
        sourceText: String? = nil,
        transcriptText: String? = nil,
        transcriptLanguage: String? = nil,
        sourceImageAssetId: String? = nil,
        sourceAudioAssetId: String? = nil,
        imageAttachment: TaskDraftImageAttachment? = nil,
        audioAttachment: TaskDraftAudioAttachment? = nil,
        categories: [Category],
        userNote: String? = nil,
        preferredSchemaPreset: CategorySchemaPreset? = nil,
        revisionInstructions: String? = nil,
        options: TaskDraftProviderOptions
    ) async throws -> LisdoDraftPipelineResult {
        let payload = LisdoCapturePayload(
            sourceType: sourceType,
            sourceText: sourceText,
            sourceImageAssetId: sourceImageAssetId,
            sourceAudioAssetId: sourceAudioAssetId,
            transcriptText: transcriptText,
            transcriptLanguage: transcriptLanguage,
            userNote: userNote,
            createdDevice: deviceType
        )

        if (imageAttachment != nil || audioAttachment != nil), !supportsDirectAttachmentProvider(provider.mode) {
            throw LisdoDraftPipelineError.unsupportedDirectAttachmentProvider(provider.mode)
        }

        let captureItem: CaptureItem
        do {
            captureItem = try LisdoCaptureFactory.makeDirectProviderCapture(
                from: payload,
                providerMode: provider.mode
            )
        } catch {
            if case LisdoCaptureUtilityError.emptyProcessableText = error {
                throw LisdoDraftPipelineError.emptySourceText
            }
            throw error
        }

        let normalizedText = try captureItem.normalizedProcessableText()
        return try await process(
            captureItem: captureItem,
            sourceText: normalizedText,
            imageAttachment: imageAttachment,
            audioAttachment: audioAttachment,
            categories: categories,
            preferredSchemaPreset: preferredSchemaPreset,
            revisionInstructions: revisionInstructions,
            options: options
        )
    }

    public func draftFromExtractedCapture(
        sourceType: CaptureSourceType,
        sourceText: String? = nil,
        transcriptText: String? = nil,
        transcriptLanguage: String? = nil,
        sourceImageAssetId: String? = nil,
        sourceAudioAssetId: String? = nil,
        imageAttachment: TaskDraftImageAttachment? = nil,
        audioAttachment: TaskDraftAudioAttachment? = nil,
        categories: [Category],
        userNote: String? = nil,
        preferredSchemaPreset: CategorySchemaPreset? = nil,
        revisionInstructions: String? = nil,
        options: TaskDraftProviderOptions
    ) async throws -> ProcessingDraft {
        try await processExtractedCapture(
            sourceType: sourceType,
            sourceText: sourceText,
            transcriptText: transcriptText,
            transcriptLanguage: transcriptLanguage,
            sourceImageAssetId: sourceImageAssetId,
            sourceAudioAssetId: sourceAudioAssetId,
            imageAttachment: imageAttachment,
            audioAttachment: audioAttachment,
            categories: categories,
            userNote: userNote,
            preferredSchemaPreset: preferredSchemaPreset,
            revisionInstructions: revisionInstructions,
            options: options
        ).draft
    }

    public func processImageCapture(
        imageData: Data,
        sourceType: CaptureSourceType = .photoImport,
        imageMimeType: String = "image/png",
        imageFilename: String? = nil,
        imageProcessingMode: LisdoImageProcessingMode = .visionOCR,
        categories: [Category],
        userNote: String? = nil,
        preferredSchemaPreset: CategorySchemaPreset? = nil,
        revisionInstructions: String? = nil,
        options: TaskDraftProviderOptions
    ) async throws -> LisdoDraftPipelineResult {
        let captureItem = CaptureItem(
            sourceType: sourceType,
            sourceText: nil,
            sourceImageAssetId: imageFilename,
            userNote: userNote,
            createdDevice: deviceType,
            status: .rawCaptured,
            preferredProviderMode: provider.mode
        )

        do {
            try captureItem.transition(to: .pendingProcessing)
            if imageProcessingMode == .directLLM {
                guard supportsDirectAttachmentProvider(provider.mode) else {
                    throw LisdoDraftPipelineError.unsupportedDirectAttachmentProvider(provider.mode)
                }
                let directImageText = "Image attachment included for direct provider analysis."
                captureItem.sourceText = directImageText
                return try await processPending(
                    captureItem: captureItem,
                    sourceText: directImageText,
                    imageAttachment: TaskDraftImageAttachment(
                        data: imageData,
                        mimeType: imageMimeType,
                        filename: imageFilename
                    ),
                    audioAttachment: nil,
                    categories: categories,
                    preferredSchemaPreset: preferredSchemaPreset,
                    revisionInstructions: revisionInstructions,
                    options: options
                )
            }

            let recognizedText = try await textRecognitionService.recognizeText(from: imageData)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !recognizedText.isEmpty else {
                try captureItem.transition(to: .processing)
                try captureItem.transition(to: .failed, error: "No OCR text found.")
                throw LisdoDraftPipelineError.emptyRecognizedText
            }

            captureItem.sourceText = recognizedText
            return try await processPending(
                captureItem: captureItem,
                sourceText: recognizedText,
                categories: categories,
                preferredSchemaPreset: preferredSchemaPreset,
                revisionInstructions: revisionInstructions,
                options: options
            )
        } catch {
            markFailedIfPossible(captureItem, error: error)
            throw error
        }
    }

    public func draftFromImageCapture(
        imageData: Data,
        sourceType: CaptureSourceType = .photoImport,
        imageMimeType: String = "image/png",
        imageFilename: String? = nil,
        imageProcessingMode: LisdoImageProcessingMode = .visionOCR,
        categories: [Category],
        userNote: String? = nil,
        preferredSchemaPreset: CategorySchemaPreset? = nil,
        revisionInstructions: String? = nil,
        options: TaskDraftProviderOptions
    ) async throws -> ProcessingDraft {
        try await processImageCapture(
            imageData: imageData,
            sourceType: sourceType,
            imageMimeType: imageMimeType,
            imageFilename: imageFilename,
            imageProcessingMode: imageProcessingMode,
            categories: categories,
            userNote: userNote,
            preferredSchemaPreset: preferredSchemaPreset,
            revisionInstructions: revisionInstructions,
            options: options
        ).draft
    }

    private func process(
        captureItem: CaptureItem,
        sourceText: String,
        imageAttachment: TaskDraftImageAttachment? = nil,
        audioAttachment: TaskDraftAudioAttachment? = nil,
        categories: [Category],
        preferredSchemaPreset: CategorySchemaPreset?,
        revisionInstructions: String?,
        options: TaskDraftProviderOptions
    ) async throws -> LisdoDraftPipelineResult {
        do {
            try captureItem.transition(to: .pendingProcessing)
            return try await processPending(
            captureItem: captureItem,
            sourceText: sourceText,
            imageAttachment: imageAttachment,
            audioAttachment: audioAttachment,
            categories: categories,
            preferredSchemaPreset: preferredSchemaPreset,
            revisionInstructions: revisionInstructions,
                options: options
            )
        } catch {
            markFailedIfPossible(captureItem, error: error)
            throw error
        }
    }

    private func processPending(
        captureItem: CaptureItem,
        sourceText: String,
        imageAttachment: TaskDraftImageAttachment? = nil,
        audioAttachment: TaskDraftAudioAttachment? = nil,
        categories: [Category],
        preferredSchemaPreset: CategorySchemaPreset?,
        revisionInstructions: String?,
        options: TaskDraftProviderOptions
    ) async throws -> LisdoDraftPipelineResult {
        try captureItem.transition(to: .processing)

        let input = TaskDraftInput(
            captureItemId: captureItem.id,
            sourceText: sourceText,
            userNote: captureItem.userNote,
            preferredSchemaPreset: preferredSchemaPreset,
            revisionInstructions: revisionInstructions,
            captureCreatedAt: captureItem.createdAt,
            timeZoneIdentifier: TimeZone.current.identifier,
            imageAttachment: imageAttachment,
            audioAttachment: audioAttachment
        )

        let draft = try await provider.generateDraft(
            input: input,
            categories: categories,
            options: options
        )

        try captureItem.transition(to: .processedDraft)
        return LisdoDraftPipelineResult(captureItem: captureItem, draft: draft)
    }

    private func markFailedIfPossible(_ captureItem: CaptureItem, error: Error) {
        if captureItem.status == .processing {
            try? captureItem.transition(to: .failed, error: String(describing: error))
        }
    }

    private func supportsDirectAttachmentProvider(_ mode: ProviderMode) -> Bool {
        switch mode {
        case .openAICompatibleBYOK, .minimax, .openRouter, .ollama, .lmStudio, .localModel:
            return true
        case .anthropic, .gemini, .macOnlyCLI:
            return false
        }
    }
}

public enum LisdoCaptureUtilityError: Error, Equatable, Sendable {
    case emptyProcessableText
    case localFallbackNotExplicitlyRequested
    case unsupportedLocalProviderMode(ProviderMode)
}

public enum LisdoCaptureFailureReason: Equatable, Sendable {
    case emptyContent
    case textRecognitionFailed(String?)
    case providerUnavailable
    case providerFailed(String?)
    case macOnlyCLIUnavailable(String?)
    case custom(String)

    public var userVisibleMessage: String {
        switch self {
        case .emptyContent:
            return "Lisdo could not find processable text in this capture. Add clearer text or try another capture source."
        case .textRecognitionFailed(let detail):
            return Self.message(
                "Lisdo could not read text from this capture. The item was saved as failed and no todo was created.",
                detail: detail
            )
        case .providerUnavailable:
            return "Provider settings are incomplete on this device. The capture was saved as failed and no todo was created."
        case .providerFailed(let detail):
            return Self.message(
                "Draft generation failed before review. The capture was saved as failed and no todo was created.",
                detail: detail
            )
        case .macOnlyCLIUnavailable(let detail):
            return Self.message(
                "Mac-only CLI processing is not available yet on this device. The capture was saved as failed and no todo was created.",
                detail: detail
            )
        case .custom(let message):
            return message.trimmedForLisdo.isEmpty
                ? "Lisdo could not process this capture. The item was saved as failed and no todo was created."
                : message.trimmedForLisdo
        }
    }

    private static func message(_ base: String, detail: String?) -> String {
        guard let detail = detail?.trimmedForLisdo, !detail.isEmpty else {
            return base
        }
        return "\(base) Details: \(detail)"
    }
}

public struct LisdoCapturePayload: Equatable, Sendable {
    public var sourceType: CaptureSourceType
    public var sourceText: String?
    public var sourceImageAssetId: String?
    public var sourceAudioAssetId: String?
    public var transcriptText: String?
    public var transcriptLanguage: String?
    public var userNote: String?
    public var createdDevice: DeviceType
    public var createdAt: Date

    public init(
        sourceType: CaptureSourceType,
        sourceText: String? = nil,
        sourceImageAssetId: String? = nil,
        sourceAudioAssetId: String? = nil,
        transcriptText: String? = nil,
        transcriptLanguage: String? = nil,
        userNote: String? = nil,
        createdDevice: DeviceType,
        createdAt: Date = Date()
    ) {
        self.sourceType = sourceType
        self.sourceText = sourceText
        self.sourceImageAssetId = sourceImageAssetId
        self.sourceAudioAssetId = sourceAudioAssetId
        self.transcriptText = transcriptText
        self.transcriptLanguage = transcriptLanguage
        self.userNote = userNote
        self.createdDevice = createdDevice
        self.createdAt = createdAt
    }
}

public enum LisdoCaptureFactory {
    public static let localDraftShellProviderId = "local-draft-shell:explicit-review"

    public static func makeMacOnlyPendingCapture(from payload: LisdoCapturePayload) throws -> CaptureItem {
        let capture = makeCapture(
            from: payload,
            status: .pendingProcessing,
            providerMode: .macOnlyCLI,
            processingError: nil
        )

        try normalizeProcessableText(on: capture)
        return capture
    }

    public static func makeDirectProviderCapture(
        from payload: LisdoCapturePayload,
        providerMode: ProviderMode
    ) throws -> CaptureItem {
        let capture = makeCapture(
            from: payload,
            status: .rawCaptured,
            providerMode: providerMode,
            processingError: nil
        )

        try normalizeProcessableText(on: capture)
        return capture
    }

    public static func makeFailedCapture(
        from payload: LisdoCapturePayload,
        providerMode: ProviderMode,
        reason: LisdoCaptureFailureReason
    ) -> CaptureItem {
        makeCapture(
            from: payload,
            status: .failed,
            providerMode: providerMode,
            processingError: reason.userVisibleMessage
        )
    }

    public static func makeExplicitLocalFallbackDraft(
        for capture: CaptureItem,
        recommendedCategoryId: String?,
        explicitlyRequested: Bool,
        generatedAt: Date = Date()
    ) throws -> ProcessingDraft {
        guard explicitlyRequested else {
            throw LisdoCaptureUtilityError.localFallbackNotExplicitlyRequested
        }

        let sourceText = try capture.normalizedProcessableText()
        markCaptureAsProcessedDraft(capture)

        return ProcessingDraft(
            captureItemId: capture.id,
            recommendedCategoryId: recommendedCategoryId,
            title: draftTitle(from: sourceText),
            summary: draftSummary(from: sourceText),
            blocks: draftBlocks(from: sourceText),
            dueDateText: inferredDueText(from: sourceText),
            priority: nil,
            confidence: 0.35,
            generatedByProvider: localDraftShellProviderId,
            generatedAt: generatedAt,
            needsClarification: false,
            questionsForUser: []
        )
    }

    public static func normalizedProcessableText(from payload: LisdoCapturePayload) throws -> String {
        let capture = makeCapture(
            from: payload,
            status: .rawCaptured,
            providerMode: .openAICompatibleBYOK,
            processingError: nil
        )
        return try capture.normalizedProcessableText()
    }

    private static func makeCapture(
        from payload: LisdoCapturePayload,
        status: CaptureStatus,
        providerMode: ProviderMode,
        processingError: String?
    ) -> CaptureItem {
        CaptureItem(
            sourceType: payload.sourceType,
            sourceText: payload.sourceText?.trimmedForLisdo.nilIfLisdoEmpty,
            sourceImageAssetId: payload.sourceImageAssetId?.trimmedForLisdo.nilIfLisdoEmpty,
            sourceAudioAssetId: payload.sourceAudioAssetId?.trimmedForLisdo.nilIfLisdoEmpty,
            transcriptText: payload.transcriptText?.trimmedForLisdo.nilIfLisdoEmpty,
            transcriptLanguage: payload.transcriptLanguage?.trimmedForLisdo.nilIfLisdoEmpty,
            userNote: payload.userNote?.trimmedForLisdo.nilIfLisdoEmpty,
            createdDevice: payload.createdDevice,
            createdAt: payload.createdAt,
            status: status,
            preferredProviderMode: providerMode,
            processingError: processingError
        )
    }

    private static func normalizeProcessableText(on capture: CaptureItem) throws {
        let normalizedText: String
        do {
            normalizedText = try capture.normalizedProcessableText()
        } catch CaptureContentNormalizationError.emptyContent {
            throw LisdoCaptureUtilityError.emptyProcessableText
        }

        switch capture.sourceType {
        case .voiceNote:
            if capture.transcriptText?.trimmedForLisdo.nilIfLisdoEmpty != nil {
                capture.transcriptText = normalizedText
            } else {
                capture.sourceText = normalizedText
            }
        default:
            if capture.transcriptText?.trimmedForLisdo.nilIfLisdoEmpty != nil {
                capture.transcriptText = normalizedText
            } else {
                capture.sourceText = normalizedText
            }
        }
    }

    private static func markCaptureAsProcessedDraft(_ capture: CaptureItem) {
        switch capture.status {
        case .rawCaptured:
            try? capture.transition(to: .pendingProcessing)
            try? capture.transition(to: .processing)
            try? capture.transition(to: .processedDraft)
        case .pendingProcessing:
            try? capture.transition(to: .processing)
            try? capture.transition(to: .processedDraft)
        case .processing:
            try? capture.transition(to: .processedDraft)
        case .failed:
            try? capture.transition(to: .retryPending)
            try? capture.transition(to: .processing)
            try? capture.transition(to: .processedDraft)
        case .retryPending:
            try? capture.transition(to: .processing)
            try? capture.transition(to: .processedDraft)
        case .processedDraft:
            capture.processingError = nil
        case .approvedTodo:
            break
        }

        capture.processingLockDeviceId = nil
        capture.processingLockCreatedAt = nil
        capture.processingError = nil
    }

    private static func draftTitle(from source: String) -> String {
        let firstLine = source
            .components(separatedBy: .newlines)
            .first?
            .trimmedForLisdo
            ?? "Review captured text"
        return firstLine.isEmpty ? "Review captured text" : String(firstLine.prefix(72))
    }

    private static func draftSummary(from source: String) -> String? {
        let collapsed = source
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard collapsed.count > 72 else { return nil }
        return String(collapsed.prefix(180))
    }

    private static func draftBlocks(from source: String) -> [DraftBlock] {
        let lines = source
            .components(separatedBy: .newlines)
            .map(\.trimmedForLisdo)
            .filter { !$0.isEmpty }

        let candidates = lines.count > 1 ? Array(lines.prefix(5)) : [draftTitle(from: source)]
        return candidates.enumerated().map { index, content in
            DraftBlock(type: .checkbox, content: content, order: index)
        }
    }

    private static func inferredDueText(from source: String) -> String? {
        let lowercased = source.lowercased()
        if lowercased.contains("today") { return "today" }
        if lowercased.contains("tomorrow") { return "tomorrow" }
        return nil
    }
}

public struct MacOnlyCLILocalSettings: Codable, Equatable, Sendable {
    public var descriptor: CLIDraftProviderDescriptor
    public var executablePath: String?

    public init(
        descriptor: CLIDraftProviderDescriptor = .codex(),
        executablePath: String? = nil
    ) {
        self.descriptor = descriptor
        self.executablePath = executablePath?.trimmedForLisdo.nilIfLisdoEmpty
    }
}

public final class LisdoLocalProviderPreferenceStore: @unchecked Sendable {
    private let userDefaults: UserDefaults

    private enum DefaultsKey {
        static let providerMode = "lisdo.provider-mode.local-preference"
        static let macOnlyCLISettings = "lisdo.mac-only-cli.local-settings"
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func readProviderMode(default defaultMode: ProviderMode = .openAICompatibleBYOK) -> ProviderMode {
        guard let rawValue = userDefaults.string(forKey: DefaultsKey.providerMode),
              let mode = ProviderMode(rawValue: rawValue),
              Self.isSupportedLocalPreference(mode)
        else {
            return defaultMode
        }

        return mode
    }

    public func saveProviderMode(_ mode: ProviderMode) throws {
        guard Self.isSupportedLocalPreference(mode) else {
            throw LisdoCaptureUtilityError.unsupportedLocalProviderMode(mode)
        }

        userDefaults.set(mode.rawValue, forKey: DefaultsKey.providerMode)
    }

    public func deleteProviderMode() {
        userDefaults.removeObject(forKey: DefaultsKey.providerMode)
    }

    public func readMacOnlyCLISettings() -> MacOnlyCLILocalSettings? {
        guard let data = userDefaults.data(forKey: DefaultsKey.macOnlyCLISettings) else {
            return nil
        }

        return try? JSONDecoder().decode(MacOnlyCLILocalSettings.self, from: data)
    }

    public func saveMacOnlyCLISettings(_ settings: MacOnlyCLILocalSettings) throws {
        let data = try JSONEncoder().encode(settings)
        userDefaults.set(data, forKey: DefaultsKey.macOnlyCLISettings)
    }

    public func deleteMacOnlyCLISettings() {
        userDefaults.removeObject(forKey: DefaultsKey.macOnlyCLISettings)
    }

    private static func isSupportedLocalPreference(_ mode: ProviderMode) -> Bool {
        ProviderMode.allCases.contains(mode)
    }
}

public enum LisdoAppGroupDefaults {
    public static let identifier = "group.com.yiwenwu.Lisdo"
    public static let pendingShareCapturePayloadsKey = "lisdo.share-extension.pending-capture-payloads"
    public static let lastShareCaptureCreatedAtKey = "lisdo.share-extension.last-capture-created-at"

    public static func userDefaults() -> UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}

private extension String {
    var trimmedForLisdo: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfLisdoEmpty: String? {
        isEmpty ? nil : self
    }
}
