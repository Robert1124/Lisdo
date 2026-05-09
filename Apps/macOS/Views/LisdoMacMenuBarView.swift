import AppKit
import LisdoCore
import SwiftData
import SwiftUI

struct LisdoMenuBarCaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \CaptureItem.createdAt, order: .reverse) private var captures: [CaptureItem]
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \Todo.updatedAt, order: .reverse) private var todos: [Todo]

    @State private var quickText = ""
    @State private var statusTitle = "Ready for capture"
    @State private var statusText = "Paste text or select a screen area. Provider output will become a draft for review."
    @State private var statusTone: LisdoCaptureStatusTone = .idle
    @State private var isProcessing = false
    @State private var isProcessingQueue = false
    @State private var isCapturingScreen = false
    @State private var isClipboardExpanded = false
    @AppStorage(LisdoCaptureModePreferences.imageProcessingModeKey)
    private var imageProcessingModeRawValue = LisdoImageProcessingMode.directLLM.rawValue

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            quickCapture
            Divider()
            pendingSection
            Divider()
            todaySection
            Divider()
            footer
        }
        .frame(width: 390)
        .background(LisdoMacTheme.surface)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.bold))
                .frame(width: 24, height: 24)
                .background(LisdoMacTheme.ink1, in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(LisdoMacTheme.onAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Lisdo")
                    .font(.headline)
                Text("Quick capture")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                openMainWindow()
            } label: {
                Image(systemName: "macwindow")
            }
            .buttonStyle(.borderless)
            .help("Open Lisdo")
        }
        .padding(14)
    }

    private var quickCapture: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button {
                    toggleClipboard()
                } label: {
                    Label("Clipboard", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .background(
                    isClipboardExpanded ? LisdoMacTheme.info.opacity(0.16) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .help(isClipboardExpanded ? "Hide clipboard text box" : "Paste clipboard text and show the text box")

                Button {
                    Task {
                        await captureScreenRegion()
                    }
                } label: {
                    Label(isCapturingScreen ? "Reading" : "Select Area", systemImage: "crop")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .disabled(isCapturingScreen || isProcessing)
                .help(imageProcessingMode == .directLLM ? "Drag to choose a screen area, then send the image to the provider" : "Drag to choose a screen area, then run Vision OCR")

                Button {
                    openVoiceCapture()
                } label: {
                    Label("Voice", systemImage: "mic")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .disabled(isProcessing || isCapturingScreen || isProcessingQueue)
                .help("Open the full capture sheet to record voice and review the transcript")
            }

            if isClipboardExpanded {
                ZStack(alignment: .bottomTrailing) {
                    TextEditor(text: $quickText)
                        .font(.callout)
                        .frame(height: 88)
                        .scrollContentBackground(.hidden)
                        .padding(.vertical, 8)
                        .padding(.leading, 8)
                        .padding(.trailing, 48)
                        .background(LisdoMacTheme.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                                .foregroundStyle(LisdoMacTheme.divider.opacity(0.9))
                        }

                    Button {
                        Task {
                            await captureText()
                        }
                    } label: {
                        Image(systemName: isProcessing ? "hourglass" : "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .disabled(quickText.lisdoTrimmed.isEmpty || isProcessing)
                    .help(isProcessing ? "Creating draft" : "Capture text as a reviewable draft")
                    .padding(10)
                    .accessibilityLabel("Capture text")
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if MacScreenCaptureService().authorizationState() != .authorized {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "lock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Screen capture permission")
                            .font(.caption.weight(.semibold))
                        Text("Allow Screen Recording to use region OCR. Text capture and queue review still work.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button("Allow") {
                        requestScreenRecordingPermission()
                    }
                    .font(.caption)
                }
                .padding(10)
                .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 10))
            }

            LisdoCaptureStatusBanner(
                title: statusTitle,
                message: statusText,
                tone: statusTone,
                showsProgress: isProcessing || isCapturingScreen || isProcessingQueue
            )
        }
        .padding(14)
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Mac processing queue")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    if !pendingCaptures.isEmpty {
                        Text("\(pendingCaptures.count) total")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .foregroundStyle(LisdoMacTheme.onAccent)
                            .background(LisdoMacTheme.ink1, in: Capsule())
                    }
                    Spacer()
                    Button {
                        Task {
                            await processAllPendingCaptures()
                        }
                    } label: {
                        Label(isProcessingQueue ? "Processing" : "Process All", systemImage: "sparkles")
                    }
                    .disabled(processablePendingCount == 0 || isProcessingQueue)
                    .help("Process pending captures into reviewable drafts with the selected provider.")
                }

                HStack(spacing: 6) {
                    QueueCountChip(title: "Pending", count: waitingPendingCount + retryPendingCount)
                    QueueCountChip(title: "Processing", count: processingPendingCount)
                    QueueCountChip(title: "Failed", count: failedPendingCount)
                    QueueCountChip(title: "Drafts", count: draftReadyCaptureCount)
                }
            }

            if pendingCaptures.isEmpty {
                LisdoCaptureStatusBanner(
                    title: "Queue empty",
                    message: "iPhone captures that require this Mac will appear here as pending items, then become drafts after processing.",
                    tone: .idle
                )
            } else {
                ForEach(pendingCaptures.prefix(3), id: \.id) { capture in
                    HStack(spacing: 9) {
                        Image(systemName: queueIcon(for: capture))
                            .foregroundStyle(queueTone(for: capture).foregroundStyle)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(capturePreview(capture))
                                .font(.caption)
                                .lineLimit(1)
                            Text(pendingStatusText(capture))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if CaptureBatchSelector.processablePendingCaptures(from: [capture]).contains(where: { $0.id == capture.id }) {
                            Button {
                                Task {
                                    await processAllPendingCaptures()
                                }
                            } label: {
                                Image(systemName: "play")
                            }
                            .buttonStyle(.borderless)
                            .help("Process pending captures into drafts for review")
                        }
                        if capture.status == .failed {
                            Button {
                                retry(capture)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Queue this failed capture for retry")
                        }
                    }
                }
            }
        }
        .padding(14)
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(todayTodos.count) left")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if todayTodos.isEmpty {
                LisdoCaptureStatusBanner(
                    title: "No approved todos due today",
                    message: "Today stays empty until you approve a draft and save it as a todo.",
                    tone: .idle
                )
            } else {
                ForEach(todayTodos.prefix(3), id: \.id) { todo in
                    HStack(spacing: 8) {
                        Image(systemName: "circle")
                            .foregroundStyle(.secondary)
                        Text(todo.title)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        if let dueDateText = todo.dueDateText {
                            Text(dueDateText)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(14)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Open Lisdo") {
                openMainWindow()
            }
            .keyboardShortcut("o", modifiers: [.command])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var pendingCaptures: [CaptureItem] {
        LisdoMacMVP2Processing.pendingQueue(from: captures)
    }

    private var processablePendingCount: Int {
        CaptureBatchSelector.processablePendingCaptures(from: pendingCaptures).count
    }

    private var failedPendingCount: Int {
        pendingCaptures.filter { $0.status == .failed }.count
    }

    private var processingPendingCount: Int {
        pendingCaptures.filter { $0.status == .processing }.count
    }

    private var waitingPendingCount: Int {
        pendingCaptures.filter { $0.status == .pendingProcessing }.count
    }

    private var retryPendingCount: Int {
        pendingCaptures.filter { $0.status == .retryPending }.count
    }

    private var draftReadyCaptureCount: Int {
        pendingCaptures.filter { $0.status == .processedDraft }.count
    }

    private var todayTodos: [Todo] {
        let calendar = Calendar.current
        return todos.filter { todo in
            todo.status != .completed
            && (
                (todo.dueDate.map(calendar.isDateInToday) ?? false)
                || (todo.scheduledDate.map(calendar.isDateInToday) ?? false)
                || todo.dueDateText?.localizedCaseInsensitiveContains("today") == true
            )
        }
    }

    private func toggleClipboard() {
        if isClipboardExpanded {
            withAnimation(.snappy) {
                isClipboardExpanded = false
            }
            return
        }

        pasteClipboard()
        withAnimation(.snappy) {
            isClipboardExpanded = true
        }
    }

    private func pasteClipboard() {
        if let text = NSPasteboard.general.string(forType: .string), !text.lisdoTrimmed.isEmpty {
            quickText = text
            setStatus(
                title: "Clipboard ready",
                message: "Review the text, then capture it as provider input for a draft.",
                tone: .idle
            )
        } else {
            quickText = ""
            setStatus(
                title: "Clipboard unavailable",
                message: "Clipboard does not contain plain text. Paste text here or use screen region OCR.",
                tone: .warning
            )
        }
    }

    @MainActor
    private func captureText() async {
        let trimmedText = quickText.lisdoTrimmed
        guard !trimmedText.isEmpty else { return }

        isProcessing = true
        setStatus(
            title: "Creating draft",
            message: "\(LisdoMacMVP2Processing.providerModeLabel) is organizing this capture. It will need review before it can become a todo.",
            tone: .processing
        )
        defer { isProcessing = false }

        let outcome = await LisdoMacMVP2Processing.processExtractedCapture(
            sourceType: .clipboard,
            sourceText: trimmedText,
            selectedCategoryId: categories.defaultCategoryId,
            categories: categories,
            modelContext: modelContext
        )
        quickText = ""
        withAnimation(.snappy) {
            isClipboardExpanded = false
        }
        setStatus(outcome)
    }

    @MainActor
    private func captureScreenRegion() async {
        guard !isCapturingScreen else { return }

        let service = MacScreenCaptureService()
        guard service.authorizationState() == .authorized else {
            let requested = service.requestScreenRecordingAccess()
            setStatus(
                title: "Permission needed",
                message: requested
                    ? "macOS requested Screen Recording permission. Enable Lisdo if prompted, then try Select Area again."
                    : "Enable Screen Recording for Lisdo in System Settings, then try Select Area again.",
                tone: .warning
            )
            return
        }

        isCapturingScreen = true
        defer { isCapturingScreen = false }

        do {
            setStatus(
                title: "Select screen area",
                message: "Drag over the text Lisdo should read. Press Escape to cancel.",
                tone: .processing
            )
            let selection = try await MacScreenRegionSelector.selectRegion()
            setStatus(
                title: imageProcessingMode == .directLLM ? "Sending screen image" : "Reading screen text",
                message: imageProcessingMode == .directLLM
                    ? "The selected region is being sent to the provider as an image attachment before draft review."
                    : "Vision OCR is extracting text before provider draft creation.",
                tone: .processing
            )
            let imageData = try await service.capturePNGData(rect: selection.captureRect, displayID: selection.displayID)
            if imageProcessingMode == .directLLM {
                let outcome = await LisdoMacMVP2Processing.processExtractedCapture(
                    sourceType: .macScreenRegion,
                    sourceText: "Image attachment included for direct provider analysis.",
                    sourceImageAssetId: "Menu bar selected screen region",
                    imageAttachment: TaskDraftImageAttachment(
                        data: imageData,
                        mimeType: "image/png",
                        filename: "Menu bar selected screen region"
                    ),
                    selectedCategoryId: categories.defaultCategoryId,
                    categories: categories,
                    modelContext: modelContext
                )
                setStatus(outcome)
                return
            }

            let recognizedText = try await VisionTextRecognitionService().recognizeText(from: imageData)
            let outcome = await LisdoMacMVP2Processing.processExtractedCapture(
                sourceType: .macScreenRegion,
                sourceText: recognizedText,
                sourceImageAssetId: "Menu bar selected screen region",
                selectedCategoryId: categories.defaultCategoryId,
                categories: categories,
                modelContext: modelContext
            )
            setStatus(outcome)
        } catch MacScreenRegionSelectionError.cancelled {
            setStatus(
                title: "Selection cancelled",
                message: "No capture was saved. Select an area again when you are ready.",
                tone: .idle
            )
        } catch {
            let item = LisdoCaptureFactory.makeFailedCapture(
                from: LisdoCapturePayload(
                    sourceType: .macScreenRegion,
                    sourceImageAssetId: "Menu bar selected screen region",
                    createdDevice: .mac
                ),
                providerMode: LisdoMacMVP2Processing.providerMode,
                reason: .textRecognitionFailed(error.localizedDescription)
            )
            modelContext.insert(item)
            try? modelContext.save()
            setStatus(
                title: "OCR capture failed",
                message: "The screen region was saved as failed before draft creation: \(error.localizedDescription)",
                tone: .failure
            )
        }
    }

    @MainActor
    private func processAllPendingCaptures() async {
        guard !isProcessingQueue else { return }

        isProcessingQueue = true
        setStatus(
            title: "Processing queue",
            message: "\(processablePendingCount) pending captures are being organized on this Mac into reviewable drafts.",
            tone: .processing
        )
        defer { isProcessingQueue = false }

        let outcome = await LisdoMacMVP2Processing.processAllQueuedCaptures(
            pendingCaptures,
            selectedCategoryId: categories.defaultCategoryId,
            categories: categories,
            modelContext: modelContext
        )
        setStatus(outcome)
    }

    private func retry(_ capture: CaptureItem) {
        let outcome = LisdoMacMVP2Processing.retryCapture(capture, modelContext: modelContext)
        setStatus(outcome)
    }

    private func pendingStatusText(_ capture: CaptureItem) -> String {
        switch capture.status {
        case .pendingProcessing:
            return "Waiting for Mac processing into a draft"
        case .processing:
            return "Processing on Mac into a draft"
        case .failed:
            return capture.processingError ?? "Failed before draft creation"
        case .retryPending:
            return "Retry queued for draft creation"
        case .processedDraft:
            return "Draft ready for review"
        case .rawCaptured:
            return "Captured, not processed into a draft"
        case .approvedTodo:
            return "Saved after review"
        }
    }

    private func capturePreview(_ capture: CaptureItem) -> String {
        let text = (capture.sourceText ?? capture.transcriptText ?? capture.userNote ?? "Pending capture").lisdoTrimmed
        return text.isEmpty ? "Pending capture" : text
    }

    private func queueIcon(for capture: CaptureItem) -> String {
        switch capture.status {
        case .pendingProcessing:
            return "tray"
        case .processing:
            return "hourglass"
        case .failed:
            return "exclamationmark.triangle"
        case .retryPending:
            return "arrow.clockwise"
        case .processedDraft:
            return "sparkles"
        case .rawCaptured:
            return "doc.text"
        case .approvedTodo:
            return "checkmark.circle"
        }
    }

    private func queueTone(for capture: CaptureItem) -> LisdoCaptureStatusTone {
        switch capture.status {
        case .pendingProcessing, .rawCaptured:
            return .idle
        case .processing:
            return .processing
        case .failed:
            return .failure
        case .retryPending:
            return .warning
        case .processedDraft, .approvedTodo:
            return .success
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
        statusText = message
        statusTone = tone
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
                message: "Enable Lisdo in macOS Screen Recording settings if prompted, then try Select Area again.",
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

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openVoiceCapture() {
        openMainWindow()
        NotificationCenter.default.post(name: LisdoMacNotifications.openCapture, object: nil)
        setStatus(
            title: "Voice capture",
            message: "Opened the capture sheet for recording, transcription, and transcript review before draft creation.",
            tone: .idle
        )
    }

    private var imageProcessingMode: LisdoImageProcessingMode {
        LisdoImageProcessingMode(rawValue: imageProcessingModeRawValue) ?? .visionOCR
    }
}

private struct QueueCountChip: View {
    let title: String
    let count: Int

    var body: some View {
        Text("\(title) \(count)")
            .font(.caption2)
            .foregroundStyle(count == 0 ? .tertiary : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(LisdoMacTheme.surface2, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(LisdoMacTheme.divider.opacity(count == 0 ? 0.55 : 0.85))
            }
    }
}
