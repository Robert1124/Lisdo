import AVFoundation
import Combine
import LisdoCore
import PhotosUI
import Speech
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

#if canImport(WidgetKit)
import WidgetKit
#endif

struct LisdoNotificationStatus: Equatable {
    var title: String
    var detail: String
    var actionTitle: String?
    var canRequestPermission: Bool
    var allowsDelivery: Bool

    static func unavailable(_ detail: String) -> LisdoNotificationStatus {
        LisdoNotificationStatus(
            title: "Notifications unavailable",
            detail: detail,
            actionTitle: nil,
            canRequestPermission: false,
            allowsDelivery: false
        )
    }
}

enum LisdoNotificationFeedback {
    static func currentStatus() async -> LisdoNotificationStatus {
        let settings = await notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            return LisdoNotificationStatus(
                title: "Notifications off",
                detail: "Lisdo can optionally send quiet updates when captures are queued, drafts are ready, or processing fails.",
                actionTitle: "Enable notifications",
                canRequestPermission: true,
                allowsDelivery: false
            )
        case .denied:
            return LisdoNotificationStatus(
                title: "Notifications disabled",
                detail: "Capture still works. Enable Lisdo notifications in Settings if you want draft-ready and queue status alerts.",
                actionTitle: nil,
                canRequestPermission: false,
                allowsDelivery: false
            )
        case .authorized, .provisional, .ephemeral:
            return LisdoNotificationStatus(
                title: "Notifications enabled",
                detail: "Lisdo may send draft-ready, queued, failed, and retry status updates. Captures never depend on notification permission.",
                actionTitle: nil,
                canRequestPermission: false,
                allowsDelivery: true
            )
        @unknown default:
            return LisdoNotificationStatus.unavailable("This device returned an unknown notification permission state.")
        }
    }

    @discardableResult
    static func requestPermission() async -> LisdoNotificationStatus {
        do {
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        } catch {
            return LisdoNotificationStatus.unavailable("Permission could not be requested: \(error.localizedDescription)")
        }

        return await currentStatus()
    }

    static func postCaptureStatus(title: String, body: String, identifier: String = UUID().uuidString) async {
        let status = await currentStatus()
        guard status.allowsDelivery else { return }

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

enum LisdoWidgetTimelineRefresh {
    static func request(reason: String) {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #else
        _ = reason
        #endif
    }
}

struct QuickCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var categories: [Category]

    @StateObject private var voiceRecorder = IOSVoiceRecorder()

    @State private var text = ""
    @State private var note = ""
    @State private var selectedCategoryId: String
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var providerMode = ProviderMode.openAICompatibleBYOK
    @State private var message: CaptureMessage?
    @State private var isProcessing = false
    @State private var isTranscribing = false
    @State private var voiceTranscript = ""
    @State private var voiceLanguageCode: String?
    @State private var isCameraPresented = false
    @AppStorage(LisdoCaptureModePreferences.imageProcessingModeKey)
    private var imageProcessingModeRawValue = LisdoImageProcessingMode.directLLM.rawValue
    @AppStorage(LisdoCaptureModePreferences.voiceProcessingModeKey)
    private var voiceProcessingModeRawValue = LisdoVoiceProcessingMode.directLLM.rawValue

    private let providerPreferenceStore = LisdoLocalProviderPreferenceStore()
    private let providerFactory = DraftProviderFactory()
    private let speechService = IOSSpeechTranscriptionService()
    private let textRecognitionService = VisionTextRecognitionService()

    init(categories: [Category]) {
        self.categories = categories
        _selectedCategoryId = State(initialValue: categories.first?.id ?? DefaultCategorySeeder.inboxCategoryId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    processingModePicker
                    textCapture
                    voiceCapture
                    visualCapture
                    categoryPicker

                    if let message {
                        CaptureMessageView(message: message)
                    }
                }
                .padding(16)
            }
            .background(LisdoTheme.surface)
            .navigationTitle("Quick capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await organizeTextCapture() }
                } label: {
                    Label(primaryActionTitle, systemImage: primaryActionIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(LisdoTheme.ink1)
                .disabled(isBusy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(16)
                .background(.thinMaterial)
            }
            .onAppear {
                providerMode = providerPreferenceStore.readProviderMode()
            }
            .onDisappear {
                voiceRecorder.discardRecording()
            }
            .onChange(of: providerMode) { _, newValue in
                try? providerPreferenceStore.saveProviderMode(newValue)
            }
            .onChange(of: selectedPhotoItem) { _, newValue in
                guard newValue != nil else { return }
                Task { await processPhotoItem(newValue) }
            }
            .sheet(isPresented: $isCameraPresented) {
                CameraCaptureView(
                    onCapture: { image in
                        isCameraPresented = false
                        Task { await processCameraImage(image) }
                    },
                    onCancel: {
                        isCameraPresented = false
                    }
                )
                .ignoresSafeArea()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Drop anything in", systemImage: "sparkle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(LisdoTheme.ink3)
            Text("Lisdo keeps AI output as a draft until you review and save it.")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(LisdoTheme.ink1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var processingModePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            LisdoSectionHeader(title: "Processing", detail: "Local-only")

            Picker("Processing mode", selection: $providerMode) {
                ForEach(DraftProviderFactory.supportedModes, id: \.self) { mode in
                    Text(DraftProviderFactory.metadata(for: mode).displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selectedProviderMetadata.isNormallyMacLocal ? "desktopcomputer" : "key")
                    .font(.system(size: 14))
                    .foregroundStyle(LisdoTheme.ink3)
                    .frame(width: 24, height: 24)
                    .background(LisdoTheme.surface3, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text(providerModeDetail)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundStyle(LisdoTheme.ink3)
            }
        }
        .lisdoCard()
    }

    private var textCapture: some View {
        VStack(alignment: .leading, spacing: 10) {
            LisdoSectionHeader(title: "Text")
            TextField("Paste text, type a thought, or add copied notes...", text: $text, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(7...12)
                .padding(14)
                .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .foregroundStyle(LisdoTheme.ink1.opacity(0.18))
                }
                .disabled(isBusy)

            TextField("Optional note for the draft", text: $note, axis: .vertical)
                .font(.system(size: 13))
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
                .disabled(isBusy)
        }
    }

    private var voiceCapture: some View {
        VStack(alignment: .leading, spacing: 10) {
            LisdoSectionHeader(title: "Voice", detail: voiceProcessingMode == .directLLM ? "Direct audio" : "Transcript review")

            HStack(spacing: 10) {
                Button {
                    if voiceRecorder.isRecording {
                        Task { await stopRecordingAndTranscribe() }
                    } else {
                        Task { await startRecording() }
                    }
                } label: {
                    Label(
                        voiceRecorder.isRecording ? voiceStopButtonTitle : "Record voice",
                        systemImage: voiceRecorder.isRecording ? "stop.circle" : "mic"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(voiceRecorder.isRecording ? LisdoTheme.warn : LisdoTheme.ink1)
                .disabled(isProcessing || isTranscribing)

                if isTranscribing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if voiceRecorder.isRecording {
                ProductStateRow(
                    icon: "waveform",
                    title: "Recording",
                    message: voiceProcessingMode == .directLLM ? "Speak naturally. Lisdo will send the audio to the provider for draft creation." : "Speak naturally. Lisdo will transcribe the audio before any draft is generated or queued."
                )
            }

            if voiceProcessingMode == .speechTranscript {
                VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Transcript review")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LisdoTheme.ink3)
                    Spacer()
                    if let voiceLanguageCode, !voiceLanguageCode.isEmpty {
                        Text(voiceLanguageCode)
                            .font(.system(size: 11))
                            .foregroundStyle(LisdoTheme.ink4)
                    }
                }

                TextField("Transcribed speech appears here for review before drafting...", text: $voiceTranscript, axis: .vertical)
                    .font(.system(size: 14))
                    .lineLimit(4...8)
                    .padding(12)
                    .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(LisdoTheme.divider.opacity(0.8), lineWidth: 1)
                    }
                    .disabled(isBusy || voiceRecorder.isRecording)

                Button {
                    Task { await submitVoiceTranscript() }
                } label: {
                    Label(secondaryActionTitle(for: "transcript"), systemImage: selectedProviderMetadata.isNormallyMacLocal ? "desktopcomputer" : "sparkle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(LisdoTheme.ink1)
                .disabled(isBusy || voiceRecorder.isRecording || voiceTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .lisdoCard(padding: 12)
            } else {
                ProductStateRow(
                    icon: "waveform.badge.magnifyingglass",
                    title: "Direct audio",
                    message: "Stopping the recording sends the temporary audio file to the selected provider. The result still lands as a draft for review."
                )
            }
        }
    }

    private var visualCapture: some View {
        VStack(alignment: .leading, spacing: 10) {
            LisdoSectionHeader(title: "Camera and images", detail: imageProcessingMode == .directLLM ? "Direct image" : "OCR")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    CaptureActionButton(
                        icon: "photo.on.rectangle",
                        title: "Import image",
                        detail: imageProcessingMode == .directLLM ? "Send the image to the provider, then review the draft." : "Run Vision OCR, then draft or queue the recognized text.",
                        isDisabled: isBusy
                    )
                }
                .buttonStyle(.plain)
                .disabled(isBusy)

                Button {
                    Task { await requestCameraAndPresent() }
                } label: {
                    CaptureActionButton(
                        icon: "camera",
                        title: "Camera",
                        detail: imageProcessingMode == .directLLM ? "Capture a photo, send it to the provider, then review the draft." : "Capture a photo, review OCR text through the same draft pipeline.",
                        isDisabled: isBusy
                    )
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            LisdoSectionHeader(title: "Preferred category")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.id) { category in
                        Button {
                            selectedCategoryId = category.id
                        } label: {
                            HStack(spacing: 6) {
                                LisdoCategoryDot(categoryId: category.id)
                                Text(category.name)
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(selectedCategoryId == category.id ? LisdoTheme.onAccent : LisdoTheme.ink2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedCategoryId == category.id ? LisdoTheme.ink1 : LisdoTheme.surface)
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().stroke(LisdoTheme.divider, lineWidth: selectedCategoryId == category.id ? 0 : 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @MainActor
    private func organizeTextCapture() async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await submitExtractedCapture(
            sourceType: .textPaste,
            sourceText: trimmed,
            transcriptText: nil,
            transcriptLanguage: nil,
            sourceImageAssetId: nil,
            sourceAudioAssetId: nil
        )
    }

    @MainActor
    private func submitVoiceTranscript() async {
        let trimmedTranscript = voiceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else { return }

        await submitExtractedCapture(
            sourceType: .voiceNote,
            sourceText: nil,
            transcriptText: trimmedTranscript,
            transcriptLanguage: voiceLanguageCode,
            sourceImageAssetId: nil,
            sourceAudioAssetId: UUID().uuidString
        )
    }

    @MainActor
    private func processPhotoItem(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        isProcessing = true
        message = imageProcessingMode == .directLLM
            ? .processing("Sending image", "Lisdo is sending the image to the selected provider before draft review.")
            : .processing("Reading image", "Vision OCR is extracting text before Lisdo creates a draft or queues this capture.")
        defer {
            isProcessing = false
            selectedPhotoItem = nil
        }

        do {
            guard let imageData = try await item.loadTransferable(type: Data.self) else {
                throw CaptureProcessingError.unreadableImage
            }
            try await processImageData(imageData, sourceType: .photoImport, sourceImageAssetId: UUID().uuidString)
        } catch {
            message = .failure("Image import failed", error.lisdoUserMessage)
        }
    }

    @MainActor
    private func processCameraImage(_ image: UIImage) async {
        isProcessing = true
        message = imageProcessingMode == .directLLM
            ? .processing("Sending photo", "Lisdo is sending the photo to the selected provider before draft review.")
            : .processing("Reading photo", "Vision OCR is extracting text before Lisdo creates a draft or queues this capture.")
        defer { isProcessing = false }

        do {
            guard let imageData = image.jpegData(compressionQuality: 0.92) ?? image.pngData() else {
                throw CaptureProcessingError.unreadableImage
            }
            try await processImageData(imageData, sourceType: .cameraImport, sourceImageAssetId: UUID().uuidString)
        } catch {
            message = .failure("Camera capture failed", error.lisdoUserMessage)
        }
    }

    @MainActor
    private func processImageData(
        _ imageData: Data,
        sourceType: CaptureSourceType,
        sourceImageAssetId: String
    ) async throws {
        if imageProcessingMode == .directLLM {
            await submitExtractedCapture(
                sourceType: sourceType,
                sourceText: "Image attachment included for direct provider analysis.",
                transcriptText: nil,
                transcriptLanguage: nil,
                sourceImageAssetId: sourceImageAssetId,
                sourceAudioAssetId: nil,
                imageAttachment: TaskDraftImageAttachment(
                    data: imageData,
                    mimeType: "image/jpeg",
                    filename: sourceImageAssetId
                ),
                managesProcessingState: false
            )
            return
        }

        let recognizedText: String
        do {
            recognizedText = try await textRecognitionService.recognizeText(from: imageData)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            saveFailedCapture(
                payload: LisdoCapturePayload(
                    sourceType: sourceType,
                    sourceImageAssetId: sourceImageAssetId,
                    userNote: trimmedNote,
                    createdDevice: .iPhone
                ),
                providerMode: providerMode,
                reason: .textRecognitionFailed(error.lisdoUserMessage)
            )
            throw error
        }

        guard !recognizedText.isEmpty else {
            saveFailedCapture(
                payload: LisdoCapturePayload(
                    sourceType: sourceType,
                    sourceImageAssetId: sourceImageAssetId,
                    userNote: trimmedNote,
                    createdDevice: .iPhone
                ),
                providerMode: providerMode,
                reason: .emptyContent
            )
            throw CaptureProcessingError.noOCRText
        }

        await submitExtractedCapture(
            sourceType: sourceType,
            sourceText: recognizedText,
            transcriptText: nil,
            transcriptLanguage: nil,
            sourceImageAssetId: sourceImageAssetId,
            sourceAudioAssetId: nil,
            managesProcessingState: false
        )
    }

    @MainActor
    private func submitExtractedCapture(
        sourceType: CaptureSourceType,
        sourceText: String?,
        transcriptText: String?,
        transcriptLanguage: String?,
        sourceImageAssetId: String?,
        sourceAudioAssetId: String?,
        imageAttachment: TaskDraftImageAttachment? = nil,
        audioAttachment: TaskDraftAudioAttachment? = nil,
        managesProcessingState: Bool = true
    ) async {
        if managesProcessingState {
            isProcessing = true
        }
        defer {
            if managesProcessingState {
                isProcessing = false
            }
        }

        let payload = LisdoCapturePayload(
            sourceType: sourceType,
            sourceText: sourceText,
            sourceImageAssetId: sourceImageAssetId,
            sourceAudioAssetId: sourceAudioAssetId,
            transcriptText: transcriptText,
            transcriptLanguage: transcriptLanguage,
            userNote: trimmedNote,
            createdDevice: .iPhone
        )

        if selectedProviderMetadata.isNormallyMacLocal {
            if imageAttachment != nil || audioAttachment != nil {
                saveFailedCapture(
                    payload: payload,
                    providerMode: providerMode,
                    reason: .custom("Direct image/audio attachments cannot be queued for Mac processing yet. Choose OCR/transcript mode or a hosted provider on this device.")
                )
                message = .failure("Direct attachment cannot queue", "Use OCR/transcript mode or select a hosted provider on this iPhone.")
                return
            }

            message = .processing("Queueing capture", "Lisdo is saving this as a pending item for Mac processing. No todo will be created until a draft is reviewed.")
            do {
                let capture = try makePendingMacCapture(from: payload, providerMode: providerMode)
                modelContext.insert(capture)
                try modelContext.save()
                LisdoWidgetTimelineRefresh.request(reason: "iOS capture queued for Mac")
                await LisdoNotificationFeedback.postCaptureStatus(
                    title: "Capture queued",
                    body: "Lisdo saved a pending capture for Mac processing.",
                    identifier: capture.id.uuidString
                )
                dismiss()
            } catch {
                saveFailedCapture(payload: payload, providerMode: providerMode, reason: .emptyContent)
                message = .failure("Capture could not be queued", error.lisdoUserMessage)
            }
            return
        }

        if hostedProviderModes.contains(providerMode) {
            do {
                guard let provider = try providerForHostedCapture() else {
                    saveFailedCapture(payload: payload, providerMode: providerMode, reason: .providerUnavailable)
                    message = .failure(
                        "Provider settings needed",
                        "No hosted API provider is configured for this capture. Add a local API key in You or choose a Mac-local queue mode."
                    )
                    return
                }

                let settings = providerFactory.loadSettings(for: providerMode)
                let pipeline = LisdoDraftPipeline(
                    provider: provider,
                    textRecognitionService: textRecognitionService,
                    deviceType: .iPhone
                )

                message = .processing("Creating draft", "Lisdo is processing this capture into a reviewable draft. No todo is saved from AI output.")
                let result = try await pipeline.processExtractedCapture(
                    sourceType: sourceType,
                    sourceText: sourceText,
                    transcriptText: transcriptText,
                    transcriptLanguage: transcriptLanguage,
                    sourceImageAssetId: sourceImageAssetId,
                    sourceAudioAssetId: sourceAudioAssetId,
                    imageAttachment: imageAttachment,
                    audioAttachment: audioAttachment,
                    categories: categories,
                    userNote: trimmedNote,
                    preferredSchemaPreset: selectedCategory?.schemaPreset,
                    options: TaskDraftProviderOptions(model: settings.model)
                )
                result.draft.recommendedCategoryId = result.draft.recommendedCategoryId ?? selectedCategoryId
                modelContext.insert(result.captureItem)
                modelContext.insert(result.draft)
                try modelContext.save()
                LisdoWidgetTimelineRefresh.request(reason: "iOS draft created")
                await LisdoNotificationFeedback.postCaptureStatus(
                    title: "Draft ready",
                    body: "Lisdo processed a capture into a draft for review.",
                    identifier: result.captureItem.id.uuidString
                )
                dismiss()
            } catch {
                saveFailedCapture(payload: payload, providerMode: providerMode, reason: .providerFailed(error.lisdoUserMessage))
                message = .failure("Draft generation failed", error.lisdoUserMessage)
            }
            return
        }

        saveFailedCapture(
            payload: payload,
            providerMode: providerMode,
            reason: .custom("This provider mode is not available on iPhone. The capture was saved as failed and no todo was created.")
        )
        message = .failure("Provider unavailable", "Choose a hosted API mode or a Mac-local queue mode.")
    }

    @MainActor
    private func startRecording() async {
        message = nil
        voiceTranscript = ""
        voiceLanguageCode = nil

        do {
            try await voiceRecorder.startRecording()
        } catch {
            message = .failure("Voice permission needed", error.lisdoUserMessage)
        }
    }

    @MainActor
    private func stopRecordingAndTranscribe() async {
        if voiceProcessingMode == .directLLM {
            await stopRecordingAndSendAudio()
            return
        }

        do {
            let recordingURL = try voiceRecorder.stopRecording()
            isTranscribing = true
            defer { isTranscribing = false }

            let transcript = try await speechService.transcribeAudio(at: recordingURL)
            voiceTranscript = transcript.text
            voiceLanguageCode = transcript.languageCode
            message = .info("Transcript ready", "Review or edit the transcript, then send it through the selected processing mode.")
        } catch {
            message = .failure("Transcription failed", error.lisdoUserMessage)
        }
    }

    @MainActor
    private func stopRecordingAndSendAudio() async {
        do {
            let recordingURL = try voiceRecorder.stopRecording()
            isProcessing = true
            defer {
                isProcessing = false
                try? FileManager.default.removeItem(at: recordingURL)
            }

            let audioData = try Data(contentsOf: recordingURL)
            await submitExtractedCapture(
                sourceType: .voiceNote,
                sourceText: "Audio attachment included for direct provider analysis.",
                transcriptText: nil,
                transcriptLanguage: nil,
                sourceImageAssetId: nil,
                sourceAudioAssetId: recordingURL.lastPathComponent,
                audioAttachment: TaskDraftAudioAttachment(
                    data: audioData,
                    format: recordingURL.pathExtension.isEmpty ? "m4a" : recordingURL.pathExtension.lowercased(),
                    filename: recordingURL.lastPathComponent
                ),
                managesProcessingState: false
            )
        } catch {
            message = .failure("Audio capture failed", error.lisdoUserMessage)
        }
    }

    @MainActor
    private func requestCameraAndPresent() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            message = .failure("Camera unavailable", "This device or simulator does not provide a camera. Use image import instead.")
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isCameraPresented = true
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
            if granted {
                isCameraPresented = true
            } else {
                message = .failure("Camera permission needed", "Enable Camera access in Settings to capture photos into Lisdo.")
            }
        case .denied, .restricted:
            message = .failure("Camera permission needed", "Enable Camera access in Settings to capture photos into Lisdo.")
        @unknown default:
            message = .failure("Camera unavailable", "Camera access is currently unavailable on this device.")
        }
    }

    private func saveFailedCapture(
        payload: LisdoCapturePayload,
        providerMode: ProviderMode,
        reason: LisdoCaptureFailureReason
    ) {
        let failed = LisdoCaptureFactory.makeFailedCapture(
            from: payload,
            providerMode: providerMode,
            reason: reason
        )
        modelContext.insert(failed)
        try? modelContext.save()
        LisdoWidgetTimelineRefresh.request(reason: "iOS capture failed")
        Task {
            await LisdoNotificationFeedback.postCaptureStatus(
                title: "Capture needs attention",
                body: reason.userVisibleMessage,
                identifier: failed.id.uuidString
            )
        }
    }

    private func providerForHostedCapture() throws -> (any TaskDraftProvider)? {
        try providerFactory.makeProvider(for: providerMode)
    }

    private func makePendingMacCapture(from payload: LisdoCapturePayload, providerMode: ProviderMode) throws -> CaptureItem {
        _ = try LisdoCaptureFactory.normalizedProcessableText(from: payload)
        return CaptureItem(
            sourceType: payload.sourceType,
            sourceText: payload.sourceText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            sourceImageAssetId: payload.sourceImageAssetId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            sourceAudioAssetId: payload.sourceAudioAssetId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            transcriptText: payload.transcriptText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            transcriptLanguage: payload.transcriptLanguage?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            userNote: payload.userNote?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            createdDevice: payload.createdDevice,
            createdAt: payload.createdAt,
            status: .pendingProcessing,
            preferredProviderMode: providerMode
        )
    }

    private var selectedCategory: Category? {
        categories.first(where: { $0.id == selectedCategoryId })
    }

    private var trimmedNote: String? {
        note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private var isBusy: Bool {
        isProcessing || isTranscribing
    }

    private var primaryActionTitle: String {
        if isProcessing { return selectedProviderMetadata.isNormallyMacLocal ? "Queueing..." : "Organizing..." }
        return selectedProviderMetadata.isNormallyMacLocal ? "Queue text for Mac" : "Organize text into a draft"
    }

    private var primaryActionIcon: String {
        selectedProviderMetadata.isNormallyMacLocal ? "desktopcomputer" : "sparkle"
    }

    private var providerModeDetail: String {
        if selectedProviderMetadata.isNormallyMacLocal {
            return "This iPhone saves processable captures to the pending queue for Mac processing. It will not call localhost or CLI tools here."
        }
        return "This iPhone uses local Keychain credentials for the selected hosted API provider. If that provider cannot be used, the capture fails for review."
    }

    private func secondaryActionTitle(for source: String) -> String {
        selectedProviderMetadata.isNormallyMacLocal ? "Queue \(source) for Mac" : "Organize \(source) into draft"
    }

    private var selectedProviderMetadata: DraftProviderModeMetadata {
        DraftProviderFactory.metadata(for: providerMode)
    }

    private var hostedProviderModes: [ProviderMode] {
        [.openAICompatibleBYOK, .minimax, .anthropic, .gemini, .openRouter]
    }

    private var imageProcessingMode: LisdoImageProcessingMode {
        LisdoImageProcessingMode(rawValue: imageProcessingModeRawValue) ?? .visionOCR
    }

    private var voiceProcessingMode: LisdoVoiceProcessingMode {
        LisdoVoiceProcessingMode(rawValue: voiceProcessingModeRawValue) ?? .speechTranscript
    }

    private var voiceStopButtonTitle: String {
        voiceProcessingMode == .directLLM ? "Stop and send audio" : "Stop and transcribe"
    }
}

private enum CaptureProcessingError: Error, LocalizedError {
    case unreadableImage
    case noOCRText

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "Lisdo could not read the image data from this capture."
        case .noOCRText:
            return "Lisdo could not find readable text in this image."
        }
    }
}

private struct CaptureMessage: Equatable {
    enum Tone {
        case info
        case processing
        case success
        case failure
    }

    var tone: Tone
    var title: String
    var detail: String

    static func info(_ title: String, _ detail: String) -> CaptureMessage {
        CaptureMessage(tone: .info, title: title, detail: detail)
    }

    static func processing(_ title: String, _ detail: String) -> CaptureMessage {
        CaptureMessage(tone: .processing, title: title, detail: detail)
    }

    static func success(_ title: String, _ detail: String) -> CaptureMessage {
        CaptureMessage(tone: .success, title: title, detail: detail)
    }

    static func failure(_ title: String, _ detail: String) -> CaptureMessage {
        CaptureMessage(tone: .failure, title: title, detail: detail)
    }
}

private struct CaptureMessageView: View {
    var message: CaptureMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.systemImage)
                .foregroundStyle(message.iconColor)
                .frame(width: 28, height: 28)
                .background(LisdoTheme.surface3, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(message.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LisdoTheme.ink1)
                Text(message.detail)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundStyle(LisdoTheme.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lisdoCard(padding: 12)
    }
}

private extension CaptureMessage {
    var systemImage: String {
        switch tone {
        case .info:
            return "info.circle"
        case .processing:
            return "clock.arrow.circlepath"
        case .success:
            return "checkmark.circle"
        case .failure:
            return "exclamationmark.triangle"
        }
    }

    var iconColor: Color {
        switch tone {
        case .info, .processing:
            return LisdoTheme.ink3
        case .success:
            return LisdoTheme.ok
        case .failure:
            return LisdoTheme.warn
        }
    }
}

private struct CaptureActionButton: View {
    var icon: String
    var title: String
    var detail: String
    var isDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(LisdoTheme.ink2)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(LisdoTheme.ink1)
            Text(detail)
                .font(.system(size: 11))
                .lineSpacing(2)
                .foregroundStyle(LisdoTheme.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(12)
        .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LisdoTheme.divider.opacity(0.8), lineWidth: 1)
        }
        .opacity(isDisabled ? 0.55 : 1)
    }
}

private extension Error {
    var lisdoUserMessage: String {
        if let localizedError = self as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        let description = localizedDescription
        return description.isEmpty ? String(describing: self) : description
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

private enum IOSVoiceCaptureError: Error, LocalizedError, Equatable {
    case microphoneDenied
    case speechDenied
    case recognizerUnavailable
    case recorderCouldNotStart
    case noActiveRecording
    case noSpeechRecognized

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone access is needed to record a voice capture. Enable it in Settings, then try again."
        case .speechDenied:
            return "Speech Recognition access is needed to turn the recording into a transcript. Enable it in Settings, then try again."
        case .recognizerUnavailable:
            return "Speech Recognition is temporarily unavailable on this iPhone. The recording was not converted into a draft."
        case .recorderCouldNotStart:
            return "Lisdo could not start recording. Check microphone access and try again."
        case .noActiveRecording:
            return "There is no active voice recording to stop."
        case .noSpeechRecognized:
            return "Lisdo could not find speech in this recording. Try again closer to the microphone."
        }
    }
}

private struct IOSSpeechTranscript: Equatable, Sendable {
    var text: String
    var languageCode: String?
}

@MainActor
private final class IOSVoiceRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false

    private var recorder: AVAudioRecorder?

    func startRecording() async throws {
        guard !isRecording else { return }

        try await requestMicrophoneAccess()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lisdo-voice-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true

        guard recorder.record() else {
            throw IOSVoiceCaptureError.recorderCouldNotStart
        }

        self.recorder = recorder
        isRecording = true
    }

    func stopRecording() throws -> URL {
        guard let recorder, isRecording else {
            throw IOSVoiceCaptureError.noActiveRecording
        }

        let url = recorder.url
        recorder.stop()
        self.recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return url
    }

    func discardRecording() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestMicrophoneAccess() async throws {
        let session = AVAudioSession.sharedInstance()

        switch session.recordPermission {
        case .granted:
            return
        case .denied:
            throw IOSVoiceCaptureError.microphoneDenied
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            guard granted else {
                throw IOSVoiceCaptureError.microphoneDenied
            }
        @unknown default:
            throw IOSVoiceCaptureError.microphoneDenied
        }
    }
}

extension IOSVoiceRecorder: AVAudioRecorderDelegate {}

private final class IOSSpeechTranscriptionService: @unchecked Sendable {
    func transcribeAudio(at url: URL, locale: Locale = .current) async throws -> IOSSpeechTranscript {
        try await requestSpeechAccess()

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw IOSVoiceCaptureError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = false

        let text: String = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            var didResume = false

            func resumeOnce(_ result: Result<String, Error>) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(with: result)
            }

            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    resumeOnce(.failure(error))
                    return
                }

                guard let result, result.isFinal else { return }

                let transcript = result.bestTranscription.formattedString
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if transcript.isEmpty {
                    resumeOnce(.failure(IOSVoiceCaptureError.noSpeechRecognized))
                } else {
                    resumeOnce(.success(transcript))
                }
            }
        }

        return IOSSpeechTranscript(text: text, languageCode: locale.identifier)
    }

    private func requestSpeechAccess() async throws {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            return
        case .denied, .restricted:
            throw IOSVoiceCaptureError.speechDenied
        case .notDetermined:
            let nextStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
            guard nextStatus == .authorized else {
                throw IOSVoiceCaptureError.speechDenied
            }
        @unknown default:
            throw IOSVoiceCaptureError.speechDenied
        }
    }
}
