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
    @EnvironmentObject private var entitlementStore: LisdoEntitlementStore

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
    @State private var imageProcessingModeRawValue = LisdoSyncedSettings.defaultImageProcessingModeRawValue
    @State private var voiceProcessingModeRawValue = LisdoSyncedSettings.defaultVoiceProcessingModeRawValue
    @State private var selectedImageData: Data?
    @State private var selectedImagePreview: UIImage?
    @State private var selectedImageSourceType: CaptureSourceType = .photoImport
    @State private var selectedImageAssetId: String?
    @State private var isVoiceCapturePresented = false
    @State private var voiceRecordingStartedAt: Date?
    @State private var recordedVoiceURL: URL?
    @State private var recordedVoiceDuration: TimeInterval?
    @State private var voiceRecordingLimitTask: Task<Void, Never>?

    private let speechService = IOSSpeechTranscriptionService()
    private let textRecognitionService = VisionTextRecognitionService()

    init(categories: [Category]) {
        self.categories = categories
        _selectedCategoryId = State(initialValue: categories.first?.id ?? DefaultCategorySeeder.inboxCategoryId)
    }

    var body: some View {
        ZStack(alignment: .top) {
            LisdoTheme.surface.ignoresSafeArea()

            Group {
                if hasPreparedImage {
                    imagePreviewDrawer
                } else {
                    quickDrawer
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LisdoTheme.surface.ignoresSafeArea())
        .presentationBackground(LisdoTheme.surface)
        .presentationDetents(quickCaptureDetents)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .onAppear {
            loadSyncedCaptureSettings()
        }
        .onDisappear {
            voiceRecorder.discardRecording()
            cancelVoiceRecordingLimit()
            discardPreparedVoice(deleteFile: true)
        }
        .onChange(of: providerMode) { _, newValue in
            saveSyncedProviderMode(newValue)
        }
        .onChange(of: imageProcessingModeRawValue) { _, newValue in
            saveSyncedImageProcessingMode(newValue)
        }
        .onChange(of: voiceProcessingModeRawValue) { _, newValue in
            saveSyncedVoiceProcessingMode(newValue)
        }
        .onChange(of: selectedPhotoItem) { _, newValue in
            guard newValue != nil else { return }
            Task { await preparePhotoItem(newValue) }
        }
        .sheet(isPresented: $isCameraPresented) {
            CameraCaptureView(
                onCapture: { image in
                    isCameraPresented = false
                    prepareCameraImage(image)
                },
                onCancel: {
                    isCameraPresented = false
                }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $isVoiceCapturePresented) {
            voiceCaptureFullScreen
        }
    }

    private var quickDrawer: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Quick capture")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LisdoTheme.ink1)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .font(.system(size: 14, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(LisdoTheme.ink3)
            }

            TextField("Paste text, type a thought, or add copied notes...", text: $text, axis: .vertical)
                .font(.system(size: 16))
                .lineLimit(4...7)
                .padding(14)
                .frame(minHeight: 132, alignment: .topLeading)
                .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .foregroundStyle(LisdoTheme.ink1.opacity(0.18))
                }
                .disabled(isBusy)

            HStack(spacing: 10) {
                QuickCaptureSourceButton(icon: "mic", title: "Voice", isDisabled: isBusy) {
                    Task { await presentVoiceCapture() }
                }

                QuickCaptureSourceButton(icon: "camera", title: "Camera", isDisabled: isBusy) {
                    Task { await requestCameraAndPresent() }
                }

                PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                    QuickCaptureSourceButtonLabel(icon: "photo.on.rectangle", title: "Photo", isDisabled: isBusy)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }

            Button {
                Task { await organizeTextCapture() }
            } label: {
                Label("Organize into a draft", systemImage: "sparkle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(LisdoTonalButtonStyle(isProminent: true, height: 54))
            .disabled(isBusy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let message {
                CaptureMessageView(message: message)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    private var imagePreviewDrawer: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let selectedImagePreview {
                Image(uiImage: selectedImagePreview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(LisdoTheme.divider.opacity(0.85), lineWidth: 1)
                    }
            }

            Button {
                Task { await organizePreparedImageCapture() }
            } label: {
                Label("Organize into a draft", systemImage: "sparkle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(LisdoTonalButtonStyle(isProminent: true, height: 58))
            .disabled(isBusy || selectedImageData == nil)

            if let message {
                CaptureMessageView(message: message)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    private var voiceCaptureFullScreen: some View {
        ZStack {
            LisdoTheme.surface.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        closeVoiceCapture()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(LisdoTheme.ink3)

                    Spacer()

                    Text("VOICE CAPTURE")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(LisdoTheme.ink3)

                    Spacer()

                    Color.clear.frame(width: 20, height: 20)
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)

                Spacer(minLength: 80)

                VoiceWaveformView(isActive: voiceRecorder.isRecording)
                    .frame(width: 260, height: 92)

                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text(voiceElapsedText(at: timeline.date))
                        .font(.system(size: 50, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(LisdoTheme.ink1)
                }
                .padding(.top, 30)

                voiceTranscriptPreviewBlock
                    .padding(.top, 22)

                if let message {
                    CaptureMessageView(message: message)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                }

                Spacer()

                voiceBottomControls
                    .padding(.horizontal, 28)
                    .padding(.bottom, 34)
            }
        }
    }

    private var voiceBottomControls: some View {
        HStack(spacing: 18) {
            Button {
                closeVoiceCapture()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.plain)
            .foregroundStyle(LisdoTheme.ink3)

            Button {
                Task {
                    if voiceRecorder.isRecording {
                        await stopVoiceCaptureForDraft()
                    } else {
                        organizePreparedVoiceCapture()
                    }
                }
            } label: {
                if voiceRecorder.isRecording {
                    ZStack {
                        Circle()
                            .fill(LisdoTheme.ink1)
                            .frame(width: 78, height: 78)
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(LisdoTheme.onAccent)
                            .frame(width: 24, height: 24)
                    }
                    .overlay {
                        Circle()
                            .stroke(LisdoTheme.onAccent, lineWidth: 4)
                            .padding(5)
                    }
                } else {
                    Label(voiceOrganizeTitle, systemImage: "sparkle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(LisdoTheme.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(LisdoTheme.ink1, in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .disabled(!voiceRecorder.isRecording && !canOrganizePreparedVoice)
            .opacity(!voiceRecorder.isRecording && !canOrganizePreparedVoice ? 0.45 : 1)

            Button {
                Task { await restartVoiceCapture() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.plain)
            .foregroundStyle(LisdoTheme.ink3)
            .disabled(isBusy)
            .opacity(isBusy ? 0.45 : 1)
        }
    }

    @ViewBuilder
    private var voiceTranscriptPreviewBlock: some View {
        let preview = voiceTranscriptPreview

        if preview.isPlaceholder {
            Text(preview.text)
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .foregroundStyle(LisdoTheme.ink3)
                .frame(maxWidth: 270)
        } else {
            VoiceTranscriptPreviewCard(text: preview.text)
                .padding(.horizontal, 34)
        }
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
            LisdoSectionHeader(title: "Processing", detail: "Synced setting")

            Picker("Processing mode", selection: $providerMode) {
                ForEach(DraftProviderFactory.supportedModes, id: \.self) { mode in
                    Text(DraftProviderFactory.metadata(for: mode).displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: providerMode == .macOnlyCLI ? "desktopcomputer" : "key")
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
            LisdoSectionHeader(title: "Voice", detail: "Transcript review")

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
                    message: "Speak naturally. Lisdo will transcribe the audio before any draft is generated or queued."
                )
            }

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
                    Label(secondaryActionTitle(for: "transcript"), systemImage: providerMode == .macOnlyCLI ? "desktopcomputer" : "sparkle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(LisdoTheme.ink1)
                .disabled(isBusy || voiceRecorder.isRecording || voiceTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .lisdoCard(padding: 12)
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
    private func preparePhotoItem(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        isProcessing = true
        message = .processing("Loading photo", "Lisdo is preparing the selected image.")
        defer {
            isProcessing = false
            selectedPhotoItem = nil
        }

        do {
            guard let imageData = try await item.loadTransferable(type: Data.self) else {
                throw CaptureProcessingError.unreadableImage
            }
            prepareImagePreview(
                imageData,
                sourceType: .photoImport,
                sourceImageAssetId: UUID().uuidString
            )
        } catch {
            message = .failure("Image import failed", error.lisdoUserMessage)
        }
    }

    @MainActor
    private func prepareCameraImage(_ image: UIImage) {
        guard let imageData = image.jpegData(compressionQuality: 0.92) ?? image.pngData() else {
            message = .failure("Camera capture failed", CaptureProcessingError.unreadableImage.lisdoUserMessage)
            return
        }
        prepareImagePreview(
            imageData,
            sourceType: .cameraImport,
            sourceImageAssetId: UUID().uuidString
        )
    }

    @MainActor
    private func prepareImagePreview(
        _ imageData: Data,
        sourceType: CaptureSourceType,
        sourceImageAssetId: String
    ) {
        guard let preview = UIImage(data: imageData) else {
            message = .failure("Image preview failed", CaptureProcessingError.unreadableImage.lisdoUserMessage)
            return
        }

        selectedImageData = imageData
        selectedImagePreview = preview
        selectedImageSourceType = sourceType
        selectedImageAssetId = sourceImageAssetId
        message = nil
    }

    @MainActor
    private func organizePreparedImageCapture() async {
        guard let selectedImageData,
              let selectedImageAssetId else { return }

        isProcessing = true
        message = imageProcessingMode == .directLLM
            ? .processing("Sending image", "Lisdo is sending the image to the selected provider before draft review.")
            : .processing("Reading image", "Vision OCR is extracting text before Lisdo creates a draft or queues this capture.")
        defer { isProcessing = false }

        do {
            try await processImageData(
                selectedImageData,
                sourceType: selectedImageSourceType,
                sourceImageAssetId: selectedImageAssetId
            )
        } catch {
            message = .failure("Image capture failed", error.lisdoUserMessage)
        }
    }

    @MainActor
    private func processImageData(
        _ imageData: Data,
        sourceType: CaptureSourceType,
        sourceImageAssetId: String
    ) async throws {
        if imageProcessingMode == .directLLM {
            let preliminaryText = await preliminaryImageText(from: imageData)
            await submitExtractedCapture(
                sourceType: sourceType,
                sourceText: preliminaryText,
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

        if providerMode == .macOnlyCLI {
            message = .processing("Queueing capture", "Lisdo is saving this as a pending item for Mac processing. No todo will be created until a draft is reviewed.")
            do {
                let capture = try makePendingCapture(from: payload, providerMode: providerMode)
                modelContext.insert(capture)
                try savePendingAttachmentIfNeeded(
                    imageAttachment: imageAttachment,
                    audioAttachment: audioAttachment,
                    captureItemId: capture.id
                )
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

        if HostedProviderQueuePolicy.isHostedProviderMode(providerMode) {
            guard canUseSelectedManagedProvider() else {
                message = managedProviderUnavailableMessage()
                return
            }

            do {
                message = .processing("Saving capture", "Lisdo is saving this locally before draft generation. AI output will still wait for review.")
                let capture = try makePendingCapture(from: payload, providerMode: providerMode)
                modelContext.insert(capture)
                try savePendingAttachmentIfNeeded(
                    imageAttachment: imageAttachment,
                    audioAttachment: audioAttachment,
                    captureItemId: capture.id
                )
                try modelContext.save()
                LisdoWidgetTimelineRefresh.request(reason: "iOS hosted capture queued")
                LisdoHostedPendingQueueProcessor.requestProcessing()
                await LisdoNotificationFeedback.postCaptureStatus(
                    title: "Capture saved",
                    body: "Lisdo saved a local pending capture and will process it into a reviewable draft.",
                    identifier: capture.id.uuidString
                )
                dismiss()
            } catch {
                saveFailedCapture(payload: payload, providerMode: providerMode, reason: .providerFailed(error.lisdoUserMessage))
                message = .failure("Capture could not be saved", error.lisdoUserMessage)
            }
            return
        }

        saveFailedCapture(
            payload: payload,
            providerMode: providerMode,
            reason: .custom("This provider mode is not available for iPhone draft generation. The capture was saved as failed and no todo was created.")
        )
        message = .failure("Provider unavailable", "Choose a hosted API mode or Mac-only CLI queue mode.")
    }

    @MainActor
    private func presentVoiceCapture() async {
        isVoiceCapturePresented = true
        await startRecording()
    }

    @MainActor
    private func startRecording() async {
        message = nil
        voiceTranscript = ""
        voiceLanguageCode = nil
        discardPreparedVoice(deleteFile: true)
        recordedVoiceDuration = nil

        do {
            try await voiceRecorder.startRecording()
            voiceRecordingStartedAt = Date()
            scheduleVoiceRecordingLimit()
        } catch {
            message = .failure("Voice permission needed", error.lisdoUserMessage)
        }
    }

    @MainActor
    private func stopVoiceCaptureForDraft(limitReached: Bool = false) async {
        cancelVoiceRecordingLimit()
        do {
            let recordingURL = try voiceRecorder.stopRecording()
            recordedVoiceURL = recordingURL
            recordedVoiceDuration = Date().timeIntervalSince(voiceRecordingStartedAt ?? Date())
            voiceRecordingStartedAt = nil

            isTranscribing = true
            message = .processing("Preparing transcript", "Lisdo is turning this recording into text before draft creation.")
            defer { isTranscribing = false }

            let transcript = try await speechService.transcribeAudio(at: recordingURL)
            voiceTranscript = transcript.text
            voiceLanguageCode = transcript.languageCode
            message = limitReached
                ? .info("Recording limit reached", "Voice captures are limited to 1 minute. Review the transcript, then organize it into a draft.")
                : nil
        } catch {
            message = .failure("Voice capture failed", error.lisdoUserMessage)
        }
    }

    @MainActor
    private func organizePreparedVoiceCapture() {
        guard let recordedVoiceURL else { return }
        submitPreparedVoiceTranscript(recordingURL: recordedVoiceURL)
    }

    @MainActor
    private func submitPreparedVoiceTranscript(recordingURL: URL) {
        let trimmedTranscript = voiceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else { return }

        let transcriptLanguage = voiceLanguageCode
        let sourceAudioAssetId = recordingURL.lastPathComponent
        discardPreparedVoice(deleteFile: true)

        if LisdoQuickCapturePresentationPolicy.dismissesVoiceAfterStartingProcessing {
            isVoiceCapturePresented = false
            dismiss()
        }

        Task { @MainActor in
            await submitExtractedCapture(
                sourceType: .voiceNote,
                sourceText: nil,
                transcriptText: trimmedTranscript,
                transcriptLanguage: transcriptLanguage,
                sourceImageAssetId: nil,
                sourceAudioAssetId: sourceAudioAssetId
            )
        }
    }

    @MainActor
    private func restartVoiceCapture() async {
        cancelVoiceRecordingLimit()
        voiceRecorder.discardRecording()
        discardPreparedVoice(deleteFile: true)
        await startRecording()
    }

    @MainActor
    private func closeVoiceCapture() {
        cancelVoiceRecordingLimit()
        voiceRecorder.discardRecording()
        discardPreparedVoice(deleteFile: true)
        isVoiceCapturePresented = false
        dismiss()
    }

    @MainActor
    private func discardPreparedVoice(deleteFile: Bool) {
        cancelVoiceRecordingLimit()
        if deleteFile, let recordedVoiceURL {
            try? FileManager.default.removeItem(at: recordedVoiceURL)
        }
        recordedVoiceURL = nil
        recordedVoiceDuration = nil
        voiceRecordingStartedAt = nil
        voiceTranscript = ""
        voiceLanguageCode = nil
    }

    @MainActor
    private func stopRecordingAndTranscribe(limitReached: Bool = false) async {
        cancelVoiceRecordingLimit()
        do {
            let recordingURL = try voiceRecorder.stopRecording()
            defer {
                try? FileManager.default.removeItem(at: recordingURL)
            }

            isTranscribing = true
            defer { isTranscribing = false }

            let transcript = try await speechService.transcribeAudio(at: recordingURL)
            voiceTranscript = transcript.text
            voiceLanguageCode = transcript.languageCode
            message = limitReached
                ? .info("Recording limit reached", "Voice captures are limited to 1 minute. Review or edit the transcript, then send it through the selected processing mode.")
                : .info("Transcript ready", "Review or edit the transcript, then send it through the selected processing mode.")
        } catch {
            message = .failure("Transcription failed", error.lisdoUserMessage)
        }
    }

    @MainActor
    private func scheduleVoiceRecordingLimit() {
        cancelVoiceRecordingLimit()
        voiceRecordingLimitTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: LisdoVoiceCapturePolicy.maximumDurationNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled, voiceRecorder.isRecording else { return }
            if isVoiceCapturePresented {
                await stopVoiceCaptureForDraft(limitReached: true)
            } else {
                await stopRecordingAndTranscribe(limitReached: true)
            }
        }
    }

    @MainActor
    private func cancelVoiceRecordingLimit() {
        voiceRecordingLimitTask?.cancel()
        voiceRecordingLimitTask = nil
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

    @MainActor
    private func loadSyncedCaptureSettings() {
        do {
            let settings = try syncedSettingsStore.fetchOrCreateSettings()
            providerMode = settings.selectedProviderMode
            imageProcessingModeRawValue = LisdoSyncedSettings.normalizedImageProcessingModeRawValue(settings.imageProcessingModeRawValue)
            voiceProcessingModeRawValue = LisdoSyncedSettings.normalizedVoiceProcessingModeRawValue(settings.voiceProcessingModeRawValue)
        } catch {
            message = .failure("Settings unavailable", "Lisdo could not load synced capture settings. \(error.lisdoUserMessage)")
        }
    }

    private func saveSyncedProviderMode(_ mode: ProviderMode) {
        do {
            try syncedSettingsStore.updateProviderMode(mode)
        } catch {
            message = .failure("Settings not saved", "The selected provider mode could not sync. \(error.lisdoUserMessage)")
        }
    }

    private func saveSyncedImageProcessingMode(_ rawValue: String) {
        do {
            let settings = try syncedSettingsStore.updateImageProcessingModeRawValue(rawValue)
            imageProcessingModeRawValue = settings.imageProcessingModeRawValue
        } catch {
            message = .failure("Settings not saved", "The image input mode could not sync. \(error.lisdoUserMessage)")
        }
    }

    private func saveSyncedVoiceProcessingMode(_ rawValue: String) {
        do {
            let settings = try syncedSettingsStore.updateVoiceProcessingModeRawValue(rawValue)
            voiceProcessingModeRawValue = settings.voiceProcessingModeRawValue
        } catch {
            message = .failure("Settings not saved", "The voice transcript mode could not sync. \(error.lisdoUserMessage)")
        }
    }

    private func preliminaryImageText(from imageData: Data) async -> String {
        do {
            let recognizedText = try await textRecognitionService.recognizeText(from: imageData)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !recognizedText.isEmpty {
                return recognizedText
            }
        } catch {
            // Raw media is still queued for Mac-only CLI direct processing.
        }

        return "Image capture queued with original media for direct provider analysis."
    }

    private func savePendingAttachmentIfNeeded(
        imageAttachment: TaskDraftImageAttachment?,
        audioAttachment: TaskDraftAudioAttachment?,
        captureItemId: UUID
    ) throws {
        let store = LisdoPendingAttachmentStore(context: modelContext)

        if let imageAttachment {
            try store.createExplicitMacCLIDirectAttachment(
                captureItemId: captureItemId,
                kind: .image,
                mimeOrFormat: imageAttachment.mimeType,
                filename: imageAttachment.filename,
                data: imageAttachment.data
            )
        }

        if let audioAttachment {
            try store.createExplicitMacCLIDirectAttachment(
                captureItemId: captureItemId,
                kind: .audio,
                mimeOrFormat: audioAttachment.format,
                filename: audioAttachment.filename,
                data: audioAttachment.data
            )
        }
    }

    private func makePendingCapture(from payload: LisdoCapturePayload, providerMode: ProviderMode) throws -> CaptureItem {
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

    private var quickCaptureDetents: Set<PresentationDetent> {
        hasPreparedImage ? [.height(440), .large] : [.height(375)]
    }

    private var hasPreparedImage: Bool {
        selectedImageData != nil && selectedImagePreview != nil
    }

    private var trimmedNote: String? {
        note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private var isBusy: Bool {
        isProcessing || isTranscribing
    }

    private var primaryActionTitle: String {
        if isProcessing { return providerMode == .macOnlyCLI ? "Queueing..." : "Organizing..." }
        return providerMode == .macOnlyCLI ? "Queue text for Mac" : "Organize text into a draft"
    }

    private var primaryActionIcon: String {
        providerMode == .macOnlyCLI ? "desktopcomputer" : "sparkle"
    }

    private var providerModeDetail: String {
        if providerMode == .macOnlyCLI {
            return "This iPhone saves captures to the pending queue for Mac processing. Images can include original media; voice captures are transcribed before queueing."
        }
        if HostedProviderQueuePolicy.isHostedProviderMode(providerMode) {
            if providerMode == .lisdoManaged {
                return "Lisdo uses the staging backend for draft creation. AI output still lands as a draft for review."
            }
            return "This iPhone uses local-only Keychain credentials for the selected hosted API provider. AI output still lands as a draft for review."
        }
        return "This provider is Mac-local. Choose Mac-only CLI to queue from iPhone, or choose a hosted API mode to draft on this device."
    }

    private func secondaryActionTitle(for source: String) -> String {
        providerMode == .macOnlyCLI ? "Queue \(source) for Mac" : "Organize \(source) into draft"
    }

    private var selectedProviderMetadata: DraftProviderModeMetadata {
        DraftProviderFactory.metadata(for: providerMode)
    }

    private var imageProcessingMode: LisdoImageProcessingMode {
        LisdoImageProcessingMode(rawValue: imageProcessingModeRawValue) ?? .visionOCR
    }

    private func canUseSelectedManagedProvider() -> Bool {
        guard providerMode == .lisdoManaged else { return true }
        return entitlementStore.effectiveSnapshot.consumingDraftUnits(1).isAllowed
    }

    private func managedProviderUnavailableMessage() -> CaptureMessage {
        let snapshot = entitlementStore.effectiveSnapshot
        if !snapshot.isFeatureEnabled(.lisdoManagedDrafts) {
            return .failure(
                "Plan upgrade needed",
                "Lisdo is available on Starter Trial and monthly plans. Refresh Lisdo after purchase, or use BYOK and Mac-local providers on Free."
            )
        }

        return .failure(
            "Lisdo quota empty",
            "This account has no Lisdo usage left. Refresh Lisdo, switch to BYOK, or choose a plan with more included usage."
        )
    }

    private var voiceProcessingMode: LisdoVoiceProcessingMode {
        LisdoVoiceProcessingMode(rawValue: voiceProcessingModeRawValue) ?? .speechTranscript
    }

    private var voiceTranscriptPreview: LisdoVoiceTranscriptPreview {
        LisdoVoiceTranscriptPreview.make(finalizedTranscript: voiceTranscript)
    }

    private var voiceStopButtonTitle: String {
        "Stop and transcribe"
    }

    private var canOrganizePreparedVoice: Bool {
        guard recordedVoiceURL != nil, !isBusy else { return false }
        return !voiceTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var voiceOrganizeTitle: String {
        if isTranscribing { return "Preparing transcript..." }
        if isProcessing { return providerMode == .macOnlyCLI ? "Queueing..." : "Organizing..." }
        return LisdoQuickCapturePresentationPolicy.voiceOrganizeTitle
    }

    private var voiceReadyDetail: String {
        if isTranscribing {
            return "Preparing the transcript before Lisdo can organize this voice capture."
        }
        return "Recording saved. Lisdo will organize the transcript as a reviewable draft."
    }

    private func voiceElapsedText(at date: Date) -> String {
        if let voiceRecordingStartedAt, voiceRecorder.isRecording {
            let elapsed = min(
                date.timeIntervalSince(voiceRecordingStartedAt),
                LisdoVoiceCapturePolicy.maximumDurationSeconds
            )
            return formatVoiceDuration(elapsed)
        }
        return formatVoiceDuration(min(recordedVoiceDuration ?? 0, LisdoVoiceCapturePolicy.maximumDurationSeconds))
    }

    private func formatVoiceDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    private var syncedSettingsStore: LisdoSyncedSettingsStore {
        LisdoSyncedSettingsStore(context: modelContext)
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

private struct QuickCaptureSourceButton: View {
    var icon: String
    var title: String
    var isDisabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            QuickCaptureSourceButtonLabel(icon: icon, title: title, isDisabled: isDisabled)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct QuickCaptureSourceButtonLabel: View {
    var icon: String
    var title: String
    var isDisabled: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(isDisabled ? LisdoTheme.ink4 : LisdoTheme.ink1)
        .frame(maxWidth: .infinity)
        .frame(height: 78)
        .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(LisdoTheme.divider.opacity(0.85), lineWidth: 1)
        }
        .opacity(isDisabled ? 0.55 : 1)
    }
}

private struct VoiceWaveformView: View {
    var isActive: Bool

    private let heights: [CGFloat] = [28, 46, 68, 86, 52, 30, 22, 34, 42, 56, 48, 38, 58, 70, 46, 30, 40, 52]

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 5) {
                ForEach(Array(heights.enumerated()), id: \.offset) { index, baseHeight in
                    Capsule()
                        .fill(LisdoTheme.ink1)
                        .frame(width: 5, height: barHeight(baseHeight, index: index, phase: phase))
                }
            }
            .opacity(isActive ? 1 : 0.62)
            .animation(.snappy(duration: 0.18), value: isActive)
        }
    }

    private func barHeight(_ baseHeight: CGFloat, index: Int, phase: TimeInterval) -> CGFloat {
        guard isActive else { return baseHeight * 0.72 }
        let wave = sin(phase * 5 + Double(index) * 0.7)
        return max(16, baseHeight + CGFloat(wave) * 12)
    }
}

private struct VoiceTranscriptPreviewCard: View {
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TRANSCRIPT")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(LisdoTheme.ink3)

            Text(text)
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(LisdoTheme.ink1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LisdoTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(LisdoTheme.divider.opacity(0.85), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
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
    var confidence: Double = 0
}

@MainActor
private final class IOSVoiceRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?

    func startRecording() async throws {
        guard !isRecording else { return }

        try await requestMicrophoneAccess()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lisdo-voice-\(UUID().uuidString)")
            .appendingPathExtension("caf")

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            try? file.write(from: buffer)
        }

        engine.prepare()

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            throw IOSVoiceCaptureError.recorderCouldNotStart
        }

        audioEngine = engine
        audioFile = file
        recordingURL = url
        isRecording = true
    }

    func stopRecording() throws -> URL {
        guard let engine = audioEngine,
              let url = recordingURL,
              isRecording else {
            throw IOSVoiceCaptureError.noActiveRecording
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioEngine = nil
        audioFile = nil
        recordingURL = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return url
    }

    func discardRecording() {
        let url = recordingURL
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        recordingURL = nil
        isRecording = false
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestMicrophoneAccess() async throws {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return
        case .denied:
            throw IOSVoiceCaptureError.microphoneDenied
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
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

private final class IOSSpeechTranscriptionService: @unchecked Sendable {
    func transcribeAudio(
        at url: URL,
        locale: Locale = .current
    ) async throws -> IOSSpeechTranscript {
        try await requestSpeechAccess()

        var lastError: Error?
        var candidates: [LisdoSpeechTranscriptCandidate] = []

        for candidateLocale in fallbackLocales(primary: locale) {
            do {
                let transcript = try await transcribeAudioOnce(at: url, locale: candidateLocale)
                candidates.append(
                    LisdoSpeechTranscriptCandidate(
                        text: transcript.text,
                        languageCode: transcript.languageCode ?? candidateLocale.identifier,
                        confidence: transcript.confidence
                    )
                )
            } catch {
                lastError = error
            }
        }

        if let bestCandidate = LisdoSpeechLocalePolicy.bestCandidate(candidates) {
            return IOSSpeechTranscript(
                text: bestCandidate.text,
                languageCode: bestCandidate.languageCode,
                confidence: bestCandidate.confidence
            )
        }

        throw lastError ?? IOSVoiceCaptureError.noSpeechRecognized
    }

    private func transcribeAudioOnce(at url: URL, locale: Locale) async throws -> IOSSpeechTranscript {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw IOSVoiceCaptureError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = false

        let transcript: IOSSpeechTranscript = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<IOSSpeechTranscript, Error>) in
            var didResume = false

            func resumeOnce(_ result: Result<IOSSpeechTranscript, Error>) {
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
                    resumeOnce(
                        .success(
                            IOSSpeechTranscript(
                                text: transcript,
                                languageCode: locale.identifier,
                                confidence: self.averageConfidence(for: result.bestTranscription)
                            )
                        )
                    )
                }
            }
        }

        return transcript
    }

    private func fallbackLocales(primary: Locale) -> [Locale] {
        LisdoSpeechLocalePolicy
            .candidateLocaleIdentifiers(primaryIdentifier: primary.identifier)
            .map(Locale.init(identifier:))
    }

    private func averageConfidence(for transcription: SFTranscription) -> Double {
        let confidences = transcription.segments.map { Double($0.confidence) }.filter { $0 > 0 }
        guard !confidences.isEmpty else { return 0.5 }
        return confidences.reduce(0, +) / Double(confidences.count)
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
