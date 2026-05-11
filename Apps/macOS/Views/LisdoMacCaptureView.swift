import AppKit
import LisdoCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum LisdoMacCaptureInitialAction {
    case text
    case selectedArea
}

struct LisdoMacCaptureRequest: Identifiable {
    let id = UUID()
    var initialAction: LisdoMacCaptureInitialAction
}

private enum LisdoMacQuickCaptureMode {
    case text
    case voice
}

struct LisdoCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let categories: [Category]
    let initialAction: LisdoMacCaptureInitialAction

    @StateObject private var voiceRecorder = MacLiveVoiceTranscriptionService()

    @State private var quickCaptureMode: LisdoMacQuickCaptureMode = .text
    @State private var captureText = ""
    @State private var userNote = ""
    @State private var selectedCategoryId: String
    @State private var showsImageImporter = false
    @State private var importedImageName: String?
    @State private var statusTitle = "Ready for capture"
    @State private var statusMessage: String?
    @State private var statusTone: LisdoCaptureStatusTone = .idle
    @State private var isRecognizingImage = false
    @State private var isProcessingText = false
    @State private var isProcessingVoice = false
    @State private var isTranscribingVoice = false
    @State private var voiceTranscript = ""
    @State private var voiceLanguageCode: String?
    @State private var lastVoiceRecordingURL: URL?
    @State private var voiceRecordingLimitTask: Task<Void, Never>?
    @State private var voiceElapsedTask: Task<Void, Never>?
    @State private var voiceElapsedSeconds = 0
    @State private var isCapturingScreen = false
    @State private var isSelectingScreenRegion = false
    @State private var screenRegionX = 0.0
    @State private var screenRegionY = 0.0
    @State private var screenRegionWidth = 900.0
    @State private var screenRegionHeight = 620.0
    @State private var hiddenWindowsForScreenSelection: [NSWindow] = []
    @Query(sort: \LisdoSyncedSettings.updatedAt, order: .reverse) private var syncedSettings: [LisdoSyncedSettings]
    @State private var selectedProviderMode: ProviderMode = .openAICompatibleBYOK
    @State private var imageProcessingModeRawValue = LisdoSyncedSettings.defaultImageProcessingModeRawValue
    @State private var voiceProcessingModeRawValue = LisdoSyncedSettings.defaultVoiceProcessingModeRawValue
    @State private var didRunInitialAction = false

    private let speechService = MacSpeechTranscriptionService()

    init(categories: [Category], initialAction: LisdoMacCaptureInitialAction = .text) {
        self.categories = categories
        self.initialAction = initialAction
        _selectedCategoryId = State(initialValue: categories.defaultCategoryId)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            quickCaptureSurface
        }
        .fileImporter(isPresented: $showsImageImporter, allowedContentTypes: [.image]) { result in
            handleImageImport(result)
        }
        .background(LisdoMacTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onAppear {
            loadSyncedSettings()
            runInitialActionIfNeeded()
        }
        .onChange(of: syncedSettingsSnapshot) { _, _ in
            loadSyncedSettings()
        }
        .onDisappear {
            cancelVoiceRecordingLimit()
            cancelVoiceElapsedTimer()
            voiceRecorder.discardRecording()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Quick capture")
                .font(.title3.weight(.semibold))
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(LisdoMacTheme.surface2.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(LisdoMacTheme.divider.opacity(0.65))
                    }
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var quickCaptureSurface: some View {
        Group {
            switch quickCaptureMode {
            case .text:
                textQuickCaptureSurface
            case .voice:
                voiceQuickCaptureSurface
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var textQuickCaptureSurface: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $captureText)
                    .font(.body)
                    .frame(minHeight: 150)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                            .foregroundStyle(LisdoMacTheme.divider.opacity(0.82))
                    }

                if captureText.lisdoTrimmed.isEmpty {
                    Text("Paste text, type a thought, or add copied notes...")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 12) {
                quickCaptureSourceButton("Voice", systemImage: "mic") {
                    enterVoiceCapture()
                }

                quickCaptureSourceButton(isSelectingScreenRegion || isCapturingScreen ? "Reading" : "Area", systemImage: "crop") {
                    Task {
                        await selectScreenRegionAndCapture()
                    }
                }
                .disabled(isSelectingScreenRegion || isCapturingScreen || isProcessingText || isProcessingVoice || isRecognizingImage)

                quickCaptureSourceButton("Photo", systemImage: "photo.on.rectangle") {
                    showsImageImporter = true
                }
                .disabled(isRecognizingImage || isProcessingText || isProcessingVoice || isCapturingScreen || isSelectingScreenRegion)
            }

            if let importedImageName {
                Label(importedImageName, systemImage: "photo")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            LisdoCaptureStatusBanner(
                title: statusTitle,
                message: statusMessage ?? "Captured input becomes a reviewable draft before it can become a todo.",
                tone: statusTone,
                showsProgress: isRecognizingImage || isProcessingText || isProcessingVoice || isTranscribingVoice || isCapturingScreen || isSelectingScreenRegion
            )

            Button {
                Task {
                    await captureTypedText()
                }
            } label: {
                Label(organizeButtonTitle, systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(canOrganize && !isVoiceBusy ? LisdoMacTheme.onAccent : LisdoMacTheme.ink4)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(canOrganize && !isVoiceBusy ? LisdoMacTheme.ink1 : LisdoMacTheme.surface3, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canOrganize || isVoiceBusy)
        }
    }

    private var voiceQuickCaptureSurface: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 4)

            LisdoMacVoiceWaveform(isActive: voiceRecorder.isRecording)
                .frame(width: 180, height: 74)
                .foregroundStyle(voiceRecorder.isRecording ? LisdoMacTheme.ink1 : LisdoMacTheme.ink3)

            Text(voiceElapsedText)
                .font(.system(size: 38, weight: .regular, design: .rounded))
                .monospacedDigit()

            VStack(alignment: .leading, spacing: 8) {
                Text("Transcript")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                TextField("Transcript appears after recording stops...", text: $voiceTranscript, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(LisdoMacTheme.divider.opacity(0.78))
                    }
            }
            .frame(maxWidth: .infinity)

            LisdoCaptureStatusBanner(
                title: statusTitle,
                message: statusMessage ?? "Speak naturally. Lisdo will transcribe the full recording after you stop.",
                tone: statusTone,
                showsProgress: voiceRecorder.isRecording || isTranscribingVoice || isProcessingVoice
            )

            HStack(spacing: 24) {
                Button {
                    discardVoiceCapture()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close voice capture")

                voicePrimaryButton

                Button {
                    Task {
                        await restartVoiceRecording()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isVoiceBusy && !voiceRecorder.isRecording)
                .help("Record again")
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 360)
    }

    @ViewBuilder
    private var voicePrimaryButton: some View {
        if !voiceRecorder.isRecording, !voiceTranscript.lisdoTrimmed.isEmpty {
            Button {
                submitVoiceTranscriptAndDismiss()
            } label: {
                Label("Organize", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(LisdoMacTheme.onAccent)
                    .frame(width: 180, height: 44)
                    .background(LisdoMacTheme.ink1, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isProcessingVoice || isTranscribingVoice)
            .keyboardShortcut(.defaultAction)
        } else {
            Button {
                Task {
                    await handleVoiceRecordButton()
                }
            } label: {
                Image(systemName: voiceRecorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(LisdoMacTheme.onAccent)
                    .frame(width: 66, height: 66)
                    .background(LisdoMacTheme.ink1, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(LisdoMacTheme.surface, lineWidth: 4)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
            }
            .buttonStyle(.plain)
            .disabled(isProcessingVoice || isTranscribingVoice)
            .keyboardShortcut(.defaultAction)
            .help(voiceRecorder.isRecording ? "Stop recording" : "Start recording")
        }
    }

    private func quickCaptureSourceButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                Text(title)
                    .font(.callout.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 82)
            .foregroundStyle(.primary)
            .background(LisdoMacTheme.surface3, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(LisdoMacTheme.divider.opacity(0.65))
            }
        }
        .buttonStyle(.plain)
    }

    private var organizeButtonTitle: String {
        if isProcessingText || isProcessingVoice || isRecognizingImage || isCapturingScreen || isSelectingScreenRegion {
            return "Organizing"
        }
        return "Organize into a draft"
    }

    private var canOrganize: Bool {
        !captureText.lisdoTrimmed.isEmpty
    }

    private func runInitialActionIfNeeded() {
        guard !didRunInitialAction else { return }
        didRunInitialAction = true
        guard initialAction == .selectedArea else { return }
        Task {
            await selectScreenRegionAndCapture()
        }
    }

    @MainActor
    private func enterVoiceCapture() {
        discardVoiceCapture()
        quickCaptureMode = .voice
        setStatus(
            title: "Voice capture",
            message: "Press record and speak naturally. Lisdo will live-transcribe English or Chinese, then send the transcript as a draft.",
            tone: .idle
        )
    }

    @MainActor
    private func handleVoiceRecordButton() async {
        if voiceRecorder.isRecording {
            await stopRecordingAndTranscribe()
        } else {
            await startVoiceRecording()
        }
    }

    @MainActor
    private func restartVoiceRecording() async {
        discardVoiceCapture()
        quickCaptureMode = .voice
        await startVoiceRecording()
    }

    @MainActor
    private func submitVoiceTranscriptAndDismiss() {
        let trimmedTranscript = voiceTranscript.lisdoTrimmed
        guard !trimmedTranscript.isEmpty else { return }

        let transcriptLanguage = voiceLanguageCode
        let trimmedNote = userNote.lisdoTrimmed.nilIfEmpty
        let categoryId = selectedCategoryId
        let categorySnapshot = categories
        voiceTranscript = ""
        voiceLanguageCode = nil
        userNote = ""
        dismiss()

        Task { @MainActor in
            _ = await LisdoMacMVP2Processing.processExtractedCapture(
                sourceType: .voiceNote,
                transcriptText: trimmedTranscript,
                transcriptLanguage: transcriptLanguage,
                sourceAudioAssetId: nil,
                userNote: trimmedNote,
                selectedCategoryId: categoryId,
                categories: categorySnapshot,
                modelContext: modelContext
            )
        }
    }

    private var voiceElapsedText: String {
        let minutes = voiceElapsedSeconds / 60
        let seconds = voiceElapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var textCapture: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Text paste", systemImage: "text.alignleft")
                    .font(.headline)
                Spacer()
                Button {
                    pasteClipboardText()
                } label: {
                    Label("Paste Clipboard", systemImage: "doc.on.clipboard")
                }
            }

            TextEditor(text: $captureText)
                .font(.body)
                .frame(minHeight: 150)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(LisdoMacTheme.divider.opacity(0.78))
                }

            TextField("Optional note for the provider", text: $userNote)
                .textFieldStyle(.roundedBorder)

            Picker("Preferred category", selection: $selectedCategoryId) {
                ForEach(categories, id: \.id) { category in
                    Text(category.name).tag(category.id)
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: 6) {
                LisdoChip(title: "Mode: \(providerModeLabel)", systemImage: "cpu")
                Text("Provider output always lands as a draft for review.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(LisdoMacTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(LisdoMacTheme.divider.opacity(0.72))
        }
    }

    private var imageCapture: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Image import", systemImage: "photo")
                    .font(.headline)
                Spacer()
                Button {
                    showsImageImporter = true
                } label: {
                    Label("Choose Image", systemImage: "square.and.arrow.down")
                }
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.viewfinder")
                    .font(.title2)
                    .frame(width: 36, height: 36)
                    .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 5) {
                    Text(importedImageName ?? "No image selected")
                        .font(.callout.weight(.medium))
                    Text(imageProcessingMode.detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(LisdoMacTheme.divider.opacity(0.72))
        }
    }

    private var voiceCapture: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Voice note", systemImage: "mic")
                    .font(.headline)
                Spacer()
                LisdoChip(title: "Transcript review", systemImage: "text.bubble")
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: voiceRecorder.isRecording ? "waveform" : "mic.circle")
                    .font(.title2)
                    .frame(width: 36, height: 36)
                    .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 5) {
                    Text(voiceHeadline)
                        .font(.callout.weight(.medium))
                    Text(voiceProcessingMode.detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button {
                    if voiceRecorder.isRecording {
                        Task {
                            await stopRecordingAndTranscribe()
                        }
                    } else {
                        Task {
                            await startVoiceRecording()
                        }
                    }
                } label: {
                    Label(
                        voiceRecorder.isRecording ? voiceStopButtonTitle : "Record Voice",
                        systemImage: voiceRecorder.isRecording ? "stop.circle" : "mic"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(isVoiceBusy)

                Button {
                    discardVoiceCapture()
                } label: {
                    Label("Discard", systemImage: "trash")
                }
                .disabled(!voiceRecorder.isRecording && voiceTranscript.lisdoTrimmed.isEmpty && lastVoiceRecordingURL == nil)

                if isTranscribingVoice {
                    ProgressView()
                        .controlSize(.small)
                    Text("Transcribing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Transcript review")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let voiceLanguageCode, !voiceLanguageCode.isEmpty {
                        Text(voiceLanguageCode)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                TextField("Transcribed speech appears here. Review or edit before creating a draft...", text: $voiceTranscript, axis: .vertical)
                    .font(.callout)
                    .lineLimit(4...8)
                    .padding(10)
                    .background(LisdoMacTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(LisdoMacTheme.divider.opacity(0.78))
                    }
                    .disabled(isVoiceBusy || voiceRecorder.isRecording)

                HStack(spacing: 8) {
                    Button {
                        Task {
                            await submitVoiceTranscript()
                        }
                    } label: {
                        Label(
                            isProcessingVoice ? "Organizing" : "Create Draft from Transcript",
                            systemImage: selectedProviderMode == .macOnlyCLI ? "desktopcomputer" : "sparkles"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(voiceRecorder.isRecording || isVoiceBusy || voiceTranscript.lisdoTrimmed.isEmpty)

                    Text("No todo is created until you review the resulting draft.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
        .background(LisdoMacTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(LisdoMacTheme.divider.opacity(0.72))
        }
    }

    private var systemCaptureSources: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System capture entries")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "crop")
                        .font(.title3)
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Screen region")
                            .font(.headline)
                        Text(imageProcessingMode == .directLLM ? "Image sent to provider, then reviewable draft" : "Vision OCR, then reviewable provider draft")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    LisdoChip(title: providerModeLabel, systemImage: "cpu")
                }

                Text(imageProcessingMode == .directLLM ? "Drag across the screen to choose the exact area Lisdo should send as an image attachment. Provider output is still stored as a reviewable draft." : "Drag across the screen to choose the exact area Lisdo should read. Lisdo runs Vision OCR, then stores provider output as a reviewable draft.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        Task {
                            await selectScreenRegionAndCapture()
                        }
                    } label: {
                        Label("Select Screen Area", systemImage: "crop")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCapturingScreen || isSelectingScreenRegion)

                    Button {
                        Task {
                            await captureMainDisplay()
                        }
                    } label: {
                        Label("Capture Display", systemImage: "display")
                    }
                    .disabled(isCapturingScreen || isSelectingScreenRegion)

                    Button {
                        requestScreenRecordingPermission()
                    } label: {
                        Label("Permission", systemImage: "lock")
                    }
                    .help("Request macOS Screen Recording permission")
                }

                if isSelectingScreenRegion || isCapturingScreen {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(isSelectingScreenRegion ? "Drag a screen region to capture" : imageProcessingMode == .directLLM ? "Capturing screen and sending image" : "Capturing screen and running OCR")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                DisclosureGroup("Coordinate fallback") {
                    VStack(alignment: .leading, spacing: 10) {
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                            GridRow {
                                Text("X")
                                    .foregroundStyle(.secondary)
                                TextField("0", value: $screenRegionX, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                Text("Y")
                                    .foregroundStyle(.secondary)
                                TextField("0", value: $screenRegionY, format: .number)
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text("Width")
                                    .foregroundStyle(.secondary)
                                TextField("900", value: $screenRegionWidth, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                Text("Height")
                                    .foregroundStyle(.secondary)
                                TextField("620", value: $screenRegionHeight, format: .number)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        Button {
                            Task {
                                await captureCustomRegion()
                            }
                        } label: {
                            Label("Capture Coordinates", systemImage: "viewfinder")
                        }
                        .disabled(isCapturingScreen || isSelectingScreenRegion || screenRegionWidth <= 0 || screenRegionHeight <= 0)
                    }
                    .padding(.top, 8)
                }
                .font(.caption)
            }
            .padding(16)
            .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(LisdoMacTheme.divider.opacity(0.72))
            }

            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Global hotkey")
                        .font(.callout.weight(.medium))
                    Text("Command-Shift-Space opens this capture sheet while Lisdo is running.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var footer: some View {
        HStack {
            LisdoCaptureStatusBanner(
                title: statusTitle,
                message: statusMessage ?? "Captured items wait for provider processing before they become drafts for review.",
                tone: statusTone,
                showsProgress: isRecognizingImage || isProcessingText || isProcessingVoice || isTranscribingVoice || isCapturingScreen || isSelectingScreenRegion
            )
            .frame(maxWidth: 420, alignment: .leading)

            Spacer()

            if isRecognizingImage {
                ProgressView()
                    .controlSize(.small)
                Text(imageProcessingMode == .directLLM ? "Sending image" : "Running Vision OCR")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(isProcessingText ? "Organizing" : "Capture Text") {
                Task {
                    await captureTypedText()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(captureText.lisdoTrimmed.isEmpty || isProcessingText)
            .keyboardShortcut(.defaultAction)
        }
        .padding(18)
    }

    private func pasteClipboardText() {
        if let text = NSPasteboard.general.string(forType: .string), !text.lisdoTrimmed.isEmpty {
            captureText = text
            setStatus(
                title: "Clipboard ready",
                message: "Review the text, then capture it as input for a draft.",
                tone: .idle
            )
        } else {
            setStatus(
                title: "Clipboard unavailable",
                message: "Clipboard does not contain plain text. Paste text here or import an image for OCR.",
                tone: .warning
            )
        }
    }

    @MainActor
    private func captureTypedText() async {
        let trimmedText = captureText.lisdoTrimmed
        guard !trimmedText.isEmpty else { return }
        let trimmedNote = userNote.lisdoTrimmed

        isProcessingText = true
        setStatus(
            title: "Creating draft",
            message: "Organizing text with \(LisdoMacMVP2Processing.providerModeLabel(modelContext: modelContext)). Review is required before saving a todo.",
            tone: .processing
        )
        defer { isProcessingText = false }

        let outcome = await LisdoMacMVP2Processing.processExtractedCapture(
            sourceType: .textPaste,
            sourceText: trimmedText,
            userNote: trimmedNote.isEmpty ? nil : trimmedNote,
            selectedCategoryId: selectedCategoryId,
            categories: categories,
            modelContext: modelContext
        )
        setStatus(outcome)
        captureText = ""
        userNote = ""
    }

    @MainActor
    private func startVoiceRecording() async {
        voiceTranscript = ""
        voiceLanguageCode = nil
        lastVoiceRecordingURL = nil
        voiceElapsedSeconds = 0

        do {
            try await voiceRecorder.startRecording { _ in }
            scheduleVoiceRecordingLimit()
            startVoiceElapsedTimer()
            setStatus(
                title: "Recording voice",
                message: "Speak naturally. Lisdo will transcribe the full recording after you stop, and will stop automatically after 1 minute.",
                tone: .processing
            )
        } catch {
            setStatus(
                title: "Microphone needed",
                message: microphonePermissionMessage(error),
                tone: .warning
            )
        }
    }

    @MainActor
    private func stopRecordingAndTranscribe(limitReached: Bool = false) async {
        cancelVoiceRecordingLimit()
        cancelVoiceElapsedTimer()
        do {
            isTranscribingVoice = true
            setStatus(
                title: limitReached ? "Recording limit reached" : "Transcribing voice",
                message: limitReached
                    ? "Voice captures are limited to 1 minute. Lisdo is finalizing the transcript for review."
                    : "Lisdo is finalizing the transcript before draft creation.",
                tone: .processing
            )
            defer { isTranscribingVoice = false }

            let result = try await voiceRecorder.stopAndTranscribe()
            voiceTranscript = result.transcript
            voiceLanguageCode = result.languageCode
            setStatus(
                title: limitReached ? "1-minute transcript ready" : "Transcript ready",
                message: "Review or edit the transcript, then create a draft. The temporary audio file was discarded.",
                tone: .success
            )
        } catch {
            setStatus(
                title: "Transcription failed",
                message: "No capture was saved. \(error.localizedDescription) You can type the transcript manually and create a draft from it.",
                tone: .failure
            )
        }
    }

    @MainActor
    private func submitVoiceTranscript() async {
        let trimmedTranscript = voiceTranscript.lisdoTrimmed
        guard !trimmedTranscript.isEmpty else { return }

        isProcessingVoice = true
        setStatus(
            title: "Creating draft",
            message: "Organizing the reviewed transcript with \(LisdoMacMVP2Processing.providerModeLabel(modelContext: modelContext)). Review is required before saving a todo.",
            tone: .processing
        )
        defer { isProcessingVoice = false }

        let outcome = await LisdoMacMVP2Processing.processExtractedCapture(
            sourceType: .voiceNote,
            transcriptText: trimmedTranscript,
            transcriptLanguage: voiceLanguageCode,
            sourceAudioAssetId: nil,
            userNote: userNote.lisdoTrimmed.nilIfEmpty,
            selectedCategoryId: selectedCategoryId,
            categories: categories,
            modelContext: modelContext
        )
        setStatus(outcome)

        switch outcome.kind {
        case .draftCreated, .pendingSaved:
            voiceTranscript = ""
            voiceLanguageCode = nil
            userNote = ""
        case .failedSaved, .skipped:
            break
        }
    }

    @MainActor
    private func discardVoiceCapture() {
        cancelVoiceRecordingLimit()
        cancelVoiceElapsedTimer()
        voiceRecorder.discardRecording()
        lastVoiceRecordingURL = nil
        voiceTranscript = ""
        voiceLanguageCode = nil
        voiceElapsedSeconds = 0
        setStatus(
            title: "Voice discarded",
            message: "No audio, transcript, draft, or todo was saved from that voice capture.",
            tone: .idle
        )
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
            await stopRecordingAndTranscribe(limitReached: true)
        }
    }

    @MainActor
    private func cancelVoiceRecordingLimit() {
        voiceRecordingLimitTask?.cancel()
        voiceRecordingLimitTask = nil
    }

    @MainActor
    private func startVoiceElapsedTimer() {
        cancelVoiceElapsedTimer()
        voiceElapsedTask = Task { @MainActor in
            while !Task.isCancelled,
                  voiceRecorder.isRecording,
                  voiceElapsedSeconds < Int(LisdoVoiceCapturePolicy.maximumDurationSeconds) {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled, voiceRecorder.isRecording else { return }
                voiceElapsedSeconds += 1
            }
        }
    }

    @MainActor
    private func cancelVoiceElapsedTimer() {
        voiceElapsedTask?.cancel()
        voiceElapsedTask = nil
    }

    private var isVoiceBusy: Bool {
        isProcessingVoice || isTranscribingVoice || isProcessingText || isRecognizingImage || isCapturingScreen || isSelectingScreenRegion
    }

    private func ensureSpeechRecognitionPermission() async throws {
        switch speechService.authorizationState() {
        case .authorized:
            return
        case .notDetermined:
            let requestedState = await speechService.requestSpeechRecognitionAuthorization()
            guard requestedState == .authorized else {
                throw MacSpeechTranscriptionError.speechRecognitionNotAuthorized(requestedState)
            }
        case .denied, .restricted:
            throw MacSpeechTranscriptionError.speechRecognitionNotAuthorized(speechService.authorizationState())
        }
    }

    private func microphonePermissionMessage(_ error: Error) -> String {
        if let voiceError = error as? MacVoiceRecordingError,
           case .microphoneNotAuthorized = voiceError {
            return "Enable Microphone access for Lisdo in System Settings, then try recording again. The capture sheet will not save audio without a reviewed transcript."
        }
        return error.localizedDescription
    }

    private func handleImageImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            importedImageName = url.lastPathComponent
            setStatus(
                title: imageProcessingMode == .directLLM ? "Image selected" : "Reading image",
                message: imageProcessingMode == .directLLM
                    ? "The image will be sent to the selected provider and saved only as a reviewable draft."
                    : "Image selected. Vision OCR is extracting text on this Mac before draft creation.",
                tone: .processing
            )
            isRecognizingImage = true
            Task {
                await recognizeImportedImage(url)
            }
        case .failure(let error):
            setStatus(
                title: "Image import failed",
                message: error.localizedDescription,
                tone: .failure
            )
        }
    }

    @MainActor
    private func recognizeImportedImage(_ url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
            isRecognizingImage = false
        }

        let trimmedNote = userNote.lisdoTrimmed

        do {
            let imageData = try Data(contentsOf: url)
            if imageProcessingMode == .directLLM {
                let outcome = await LisdoMacMVP2Processing.processExtractedCapture(
                    sourceType: .photoImport,
                    sourceText: "Image attachment included for direct provider analysis.",
                    sourceImageAssetId: url.lastPathComponent,
                    imageAttachment: TaskDraftImageAttachment(
                        data: imageData,
                        mimeType: imageMimeType(for: url),
                        filename: url.lastPathComponent
                    ),
                    userNote: trimmedNote.isEmpty ? nil : trimmedNote,
                    selectedCategoryId: selectedCategoryId,
                    categories: categories,
                    modelContext: modelContext
                )
                setStatus(outcome)
                userNote = ""
                return
            }

            let recognizedText = try await VisionTextRecognitionService()
                .recognizeText(from: imageData)
                .lisdoTrimmed

            let outcome = await LisdoMacMVP2Processing.processExtractedCapture(
                sourceType: .photoImport,
                sourceText: recognizedText,
                sourceImageAssetId: url.lastPathComponent,
                userNote: trimmedNote.isEmpty ? nil : trimmedNote,
                selectedCategoryId: selectedCategoryId,
                categories: categories,
                modelContext: modelContext
            )
            setStatus(outcome)
            userNote = ""
        } catch {
            let item = LisdoCaptureFactory.makeFailedCapture(
                from: LisdoCapturePayload(
                    sourceType: .photoImport,
                    sourceImageAssetId: url.lastPathComponent,
                    userNote: trimmedNote.isEmpty ? "Image import failed before a draft was created." : trimmedNote,
                    createdDevice: .mac
                ),
                providerMode: LisdoMacMVP2Processing.providerMode(modelContext: modelContext),
                reason: .textRecognitionFailed(error.localizedDescription)
            )
            modelContext.insert(item)
            try? modelContext.save()
            setStatus(
                title: "OCR failed",
                message: "Image capture was saved as failed before draft creation: \(error.localizedDescription)",
                tone: .failure
            )
        }
    }

    @MainActor
    private func captureMainDisplay() async {
        await captureScreenRegion(
            imageAssetId: "Main display screen capture",
            capture: { service in
                try await service.captureMainDisplayPNGData()
            }
        )
    }

    @MainActor
    private func captureCustomRegion() async {
        let rect = CGRect(
            x: screenRegionX,
            y: screenRegionY,
            width: screenRegionWidth,
            height: screenRegionHeight
        )
        await captureScreenRegion(
            imageAssetId: "Screen region \(Int(rect.origin.x)),\(Int(rect.origin.y)) \(Int(rect.width))x\(Int(rect.height))",
            capture: { service in
                try await service.capturePNGData(rect: rect)
            }
        )
    }

    @MainActor
    private func selectScreenRegionAndCapture() async {
        guard !isCapturingScreen, !isSelectingScreenRegion else { return }

        let service = MacScreenCaptureService()
        guard service.authorizationState() == .authorized else {
            let requested = service.requestScreenRecordingAccess()
            setStatus(
                title: "Permission needed",
                message: requested
                    ? "macOS requested Screen Recording permission. Enable Lisdo if prompted, then try Select Screen Area again."
                    : "Enable Screen Recording for Lisdo in System Settings, then try Select Screen Area again.",
                tone: .warning
            )
            return
        }

        isSelectingScreenRegion = true
        setStatus(
            title: "Select screen area",
            message: "Drag over the text Lisdo should read. Press Escape to cancel.",
            tone: .processing
        )

        let selection: MacScreenRegionSelection
        hideLisdoWindowsForScreenSelection()
        defer {
            restoreLisdoWindowsAfterScreenSelection()
        }
        do {
            selection = try await MacScreenRegionSelector.selectRegion()
        } catch MacScreenRegionSelectionError.cancelled {
            isSelectingScreenRegion = false
            setStatus(
                title: "Selection cancelled",
                message: "No capture was saved. Select an area again when you are ready.",
                tone: .idle
            )
            return
        } catch {
            isSelectingScreenRegion = false
            setStatus(
                title: "Selection failed",
                message: "Screen region selection failed before OCR: \(error.localizedDescription)",
                tone: .failure
            )
            return
        }

        isSelectingScreenRegion = false
        screenRegionX = selection.captureRect.origin.x
        screenRegionY = selection.captureRect.origin.y
        screenRegionWidth = selection.captureRect.width
        screenRegionHeight = selection.captureRect.height

        await captureScreenRegion(
            imageAssetId: "Selected screen region \(Int(selection.captureRect.origin.x)),\(Int(selection.captureRect.origin.y)) \(Int(selection.captureRect.width))x\(Int(selection.captureRect.height))",
            capture: { service in
                try await service.capturePNGData(rect: selection.captureRect, displayID: selection.displayID)
            }
        )
    }

    @MainActor
    private func captureScreenRegion(
        imageAssetId: String,
        capture: @escaping (MacScreenCaptureService) async throws -> Data
    ) async {
        guard !isCapturingScreen else { return }

        let service = MacScreenCaptureService()
        guard service.authorizationState() == .authorized else {
            let requested = service.requestScreenRecordingAccess()
            setStatus(
                title: "Permission needed",
                message: requested
                    ? "macOS requested Screen Recording permission. Enable Lisdo if prompted, then try again."
                    : "Enable Screen Recording for Lisdo in System Settings, then try again.",
                tone: .warning
            )
            return
        }

        isCapturingScreen = true
        setStatus(
            title: imageProcessingMode == .directLLM ? "Sending screen image" : "Reading screen text",
            message: imageProcessingMode == .directLLM
                ? "Capturing the selected region and sending the image to the selected provider for a reviewable draft."
                : "Capturing the screen region and running Vision OCR before draft creation.",
            tone: .processing
        )
        defer { isCapturingScreen = false }

        do {
            let imageData = try await capture(service)
            if imageProcessingMode == .directLLM {
                let outcome = await LisdoMacMVP2Processing.processExtractedCapture(
                    sourceType: .macScreenRegion,
                    sourceText: "Image attachment included for direct provider analysis.",
                    sourceImageAssetId: imageAssetId,
                    imageAttachment: TaskDraftImageAttachment(
                        data: imageData,
                        mimeType: "image/png",
                        filename: imageAssetId
                    ),
                    userNote: userNote.lisdoTrimmed.nilIfEmpty,
                    selectedCategoryId: selectedCategoryId,
                    categories: categories,
                    modelContext: modelContext
                )
                setStatus(outcome)
                return
            }

            let recognizedText = try await VisionTextRecognitionService()
                .recognizeText(from: imageData)
                .lisdoTrimmed
            let outcome = await LisdoMacMVP2Processing.processExtractedCapture(
                sourceType: .macScreenRegion,
                sourceText: recognizedText,
                sourceImageAssetId: imageAssetId,
                userNote: userNote.lisdoTrimmed.nilIfEmpty,
                selectedCategoryId: selectedCategoryId,
                categories: categories,
                modelContext: modelContext
            )
            setStatus(outcome)
        } catch {
            let item = LisdoCaptureFactory.makeFailedCapture(
                from: LisdoCapturePayload(
                    sourceType: .macScreenRegion,
                    sourceImageAssetId: imageAssetId,
                    userNote: userNote.lisdoTrimmed.nilIfEmpty,
                    createdDevice: .mac
                ),
                providerMode: LisdoMacMVP2Processing.providerMode(modelContext: modelContext),
                reason: .textRecognitionFailed(error.localizedDescription)
            )
            modelContext.insert(item)
            try? modelContext.save()
            setStatus(
                title: "OCR capture failed",
                message: "Screen capture was saved as failed before draft creation: \(error.localizedDescription)",
                tone: .failure
            )
        }
    }

    private func requestScreenRecordingPermission() {
        let service = MacScreenCaptureService()
        if service.authorizationState() == .authorized {
            setStatus(
                title: "Permission ready",
                message: "Screen region capture can run Vision OCR before creating a reviewable draft.",
                tone: .success
            )
        } else if service.requestScreenRecordingAccess() {
            setStatus(
                title: "Permission requested",
                message: "Enable Lisdo in macOS Screen Recording settings if prompted, then try screen capture again.",
                tone: .warning
            )
        } else {
            setStatus(
                title: "Permission needed",
                message: "Open System Settings and allow Screen Recording for Lisdo before using region OCR.",
                tone: .warning
            )
        }
    }

    private func setStatus(_ outcome: LisdoMacProcessingOutcome) {
        switch outcome.kind {
        case .draftCreated:
            setStatus(title: "Draft ready", message: outcome.message, tone: .success)
        case .pendingSaved:
            setStatus(title: "Capture pending", message: outcome.message, tone: .warning)
        case .failedSaved:
            setStatus(title: "Needs attention", message: outcome.message, tone: .failure)
        case .skipped:
            setStatus(title: "No queue change", message: outcome.message, tone: .idle)
        }
    }

    private func setStatus(title: String, message: String, tone: LisdoCaptureStatusTone) {
        statusTitle = title
        statusMessage = message
        statusTone = tone
    }

    private var syncedSettingsSnapshot: String {
        guard let settings = syncedSettings.first else {
            return "missing"
        }

        return [
            settings.selectedProviderMode.rawValue,
            settings.imageProcessingModeRawValue,
            settings.voiceProcessingModeRawValue,
            String(settings.updatedAt.timeIntervalSinceReferenceDate)
        ].joined(separator: "|")
    }

    private func loadSyncedSettings() {
        do {
            let settings = try LisdoMacMVP2Processing.syncedSettings(modelContext: modelContext)
            selectedProviderMode = settings.selectedProviderMode
            imageProcessingModeRawValue = settings.imageProcessingModeRawValue
            voiceProcessingModeRawValue = settings.voiceProcessingModeRawValue
        } catch {
            selectedProviderMode = LisdoMacMVP2Processing.providerMode(modelContext: modelContext)
            imageProcessingModeRawValue = LisdoMacMVP2Processing.imageProcessingMode(modelContext: modelContext).rawValue
            voiceProcessingModeRawValue = LisdoMacMVP2Processing.voiceProcessingMode(modelContext: modelContext).rawValue
        }
    }

    private var providerModeLabel: String {
        DraftProviderFactory.metadata(for: selectedProviderMode).displayName
    }

    private var imageProcessingMode: LisdoImageProcessingMode {
        LisdoImageProcessingMode(rawValue: imageProcessingModeRawValue) ?? .visionOCR
    }

    private var voiceProcessingMode: LisdoVoiceProcessingMode {
        LisdoVoiceProcessingMode(rawValue: voiceProcessingModeRawValue) ?? .speechTranscript
    }

    private var voiceHeadline: String {
        if voiceRecorder.isRecording {
            return "Recording on this Mac"
        }
        return "Record, transcribe, then review"
    }

    private var voiceStopButtonTitle: String {
        "Stop and Transcribe"
    }

    private func imageMimeType(for url: URL) -> String {
        guard let type = UTType(filenameExtension: url.pathExtension),
              let mimeType = type.preferredMIMEType
        else {
            return "image/png"
        }
        return mimeType
    }

    private func hideLisdoWindowsForScreenSelection() {
        hiddenWindowsForScreenSelection = NSApp.windows.filter { window in
            window.isVisible && window.level.rawValue < NSWindow.Level.screenSaver.rawValue
        }
        hiddenWindowsForScreenSelection.forEach { window in
            window.orderOut(nil)
        }
    }

    private func restoreLisdoWindowsAfterScreenSelection() {
        hiddenWindowsForScreenSelection.forEach { window in
            window.makeKeyAndOrderFront(nil)
        }
        hiddenWindowsForScreenSelection = []
        NSApp.activate(ignoringOtherApps: true)
    }

}

private struct LisdoMacVoiceWaveform: View {
    var isActive: Bool

    private let bars: [CGFloat] = [0.58, 0.76, 1.0, 0.82, 0.62, 0.46, 0.34, 0.28, 0.42, 0.56, 0.72, 0.84, 0.68, 0.54, 0.66, 0.78, 0.94, 0.72]

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(bars.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .frame(width: 4, height: 54 * height)
                    .opacity(isActive ? (index.isMultiple(of: 2) ? 1 : 0.72) : 0.35)
                    .animation(
                        isActive
                            ? .easeInOut(duration: 0.55 + Double(index % 4) * 0.08).repeatForever(autoreverses: true)
                            : .default,
                        value: isActive
                    )
            }
        }
        .accessibilityHidden(true)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
