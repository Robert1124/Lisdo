import AppKit
import LisdoCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LisdoCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let categories: [Category]

    @StateObject private var voiceRecorder = MacVoiceRecordingService()

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
    @State private var isCapturingScreen = false
    @State private var isSelectingScreenRegion = false
    @State private var screenRegionX = 0.0
    @State private var screenRegionY = 0.0
    @State private var screenRegionWidth = 900.0
    @State private var screenRegionHeight = 620.0
    @AppStorage(LisdoCaptureModePreferences.imageProcessingModeKey)
    private var imageProcessingModeRawValue = LisdoImageProcessingMode.directLLM.rawValue
    @AppStorage(LisdoCaptureModePreferences.voiceProcessingModeKey)
    private var voiceProcessingModeRawValue = LisdoVoiceProcessingMode.directLLM.rawValue

    private let speechService = MacSpeechTranscriptionService()

    init(categories: [Category]) {
        self.categories = categories
        _selectedCategoryId = State(initialValue: categories.defaultCategoryId)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    textCapture
                    voiceCapture
                    imageCapture
                    systemCaptureSources
                }
                .padding(20)
            }
            .background(LisdoMacTheme.surface)
            Divider()
            footer
        }
        .fileImporter(isPresented: $showsImageImporter, allowedContentTypes: [.image]) { result in
            handleImageImport(result)
        }
        .onDisappear {
            voiceRecorder.discardRecording()
            if let lastVoiceRecordingURL {
                voiceRecorder.discardRecording(at: lastVoiceRecordingURL)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .frame(width: 30, height: 30)
                .background(LisdoMacTheme.ink1, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(LisdoMacTheme.onAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Quick capture")
                    .font(.headline)
                Text("Capture now, review the AI draft before saving a todo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(18)
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
                LisdoChip(title: "Mode: \(LisdoMacMVP2Processing.providerModeLabel)", systemImage: "cpu")
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
                    .opacity(voiceProcessingMode == .speechTranscript ? 1 : 0)
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

            if voiceProcessingMode == .speechTranscript {
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
                            systemImage: LisdoMacMVP2Processing.providerMode == .macOnlyCLI ? "desktopcomputer" : "sparkles"
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
            } else {
                Text("Stopping the recording sends the temporary audio file to the selected provider. Review still happens in the resulting draft.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
            }
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
                    LisdoChip(title: LisdoMacMVP2Processing.providerModeLabel, systemImage: "cpu")
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
            message: "Organizing text with \(LisdoMacMVP2Processing.providerModeLabel). Review is required before saving a todo.",
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
        if let lastVoiceRecordingURL {
            voiceRecorder.discardRecording(at: lastVoiceRecordingURL)
            self.lastVoiceRecordingURL = nil
        }

        do {
            try await voiceRecorder.startRecording()
            setStatus(
                title: "Recording voice",
                message: voiceProcessingMode == .directLLM
                    ? "Speak naturally. Stop recording to send the audio to the selected provider for a reviewable draft."
                    : "Speak naturally. Stop recording to create an editable transcript before any draft is generated.",
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
    private func stopRecordingAndTranscribe() async {
        if voiceProcessingMode == .directLLM {
            await stopRecordingAndSendAudioToProvider()
            return
        }

        do {
            let recordingURL = try voiceRecorder.stopRecording()
            lastVoiceRecordingURL = recordingURL
            isTranscribingVoice = true
            setStatus(
                title: "Transcribing voice",
                message: "Speech recognition is creating a transcript for review. Audio remains in a temporary local file.",
                tone: .processing
            )
            defer { isTranscribingVoice = false }

            try await ensureSpeechRecognitionPermission()
            let result = try await speechService.transcribeAudioFile(at: recordingURL)
            voiceTranscript = result.transcript
            voiceLanguageCode = Locale.current.identifier
            voiceRecorder.discardRecording(at: recordingURL)
            lastVoiceRecordingURL = nil
            setStatus(
                title: "Transcript ready",
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
    private func stopRecordingAndSendAudioToProvider() async {
        do {
            let recordingURL = try voiceRecorder.stopRecording()
            lastVoiceRecordingURL = recordingURL
            isProcessingVoice = true
            setStatus(
                title: "Sending audio",
                message: "The selected provider will transcribe and organize this audio into a draft for review.",
                tone: .processing
            )
            defer { isProcessingVoice = false }

            let audioData = try Data(contentsOf: recordingURL)
            let outcome = await LisdoMacMVP2Processing.processExtractedCapture(
                sourceType: .voiceNote,
                sourceText: "Audio attachment included for direct provider analysis.",
                sourceAudioAssetId: recordingURL.lastPathComponent,
                audioAttachment: TaskDraftAudioAttachment(
                    data: audioData,
                    format: audioFormat(for: recordingURL),
                    filename: recordingURL.lastPathComponent
                ),
                userNote: userNote.lisdoTrimmed.nilIfEmpty,
                selectedCategoryId: selectedCategoryId,
                categories: categories,
                modelContext: modelContext
            )
            voiceRecorder.discardRecording(at: recordingURL)
            lastVoiceRecordingURL = nil
            userNote = ""
            setStatus(outcome)
        } catch {
            setStatus(
                title: "Audio capture failed",
                message: "No capture was saved. \(error.localizedDescription)",
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
            message: "Organizing the reviewed transcript with \(LisdoMacMVP2Processing.providerModeLabel). Review is required before saving a todo.",
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
        voiceRecorder.discardRecording()
        if let lastVoiceRecordingURL {
            voiceRecorder.discardRecording(at: lastVoiceRecordingURL)
            self.lastVoiceRecordingURL = nil
        }
        voiceTranscript = ""
        voiceLanguageCode = nil
        setStatus(
            title: "Voice discarded",
            message: "No audio, transcript, draft, or todo was saved from that voice capture.",
            tone: .idle
        )
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
                providerMode: LisdoMacMVP2Processing.providerMode,
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
                providerMode: LisdoMacMVP2Processing.providerMode,
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
        return voiceProcessingMode == .directLLM ? "Record, send audio, then review" : "Record, transcribe, then review"
    }

    private var voiceStopButtonTitle: String {
        voiceProcessingMode == .directLLM ? "Stop and Send Audio" : "Stop and Transcribe"
    }

    private func imageMimeType(for url: URL) -> String {
        guard let type = UTType(filenameExtension: url.pathExtension),
              let mimeType = type.preferredMIMEType
        else {
            return "image/png"
        }
        return mimeType
    }

    private func audioFormat(for url: URL) -> String {
        let ext = url.pathExtension.lisdoTrimmed.lowercased()
        return ext.isEmpty ? "m4a" : ext
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
