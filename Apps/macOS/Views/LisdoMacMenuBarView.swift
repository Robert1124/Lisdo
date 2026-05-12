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
    @Query(sort: \LisdoSyncedSettings.updatedAt, order: .reverse) private var syncedSettings: [LisdoSyncedSettings]
    @State private var selectedProviderMode: ProviderMode = .openAICompatibleBYOK
    @State private var imageProcessingModeRawValue = LisdoSyncedSettings.defaultImageProcessingModeRawValue

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            pendingSection
            Divider()
            todaySection
            Divider()
            quitRow
        }
        .frame(width: 340)
        .modifier(LisdoMenuBarGlassWindowBackground())
        .onAppear(perform: loadSyncedSettings)
        .onChange(of: syncedSettingsSnapshot) { _, _ in
            loadSyncedSettings()
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            LisdoLogoMark(size: 24, cornerRadius: 7)
            Text("Lisdo")
                .font(.headline)
            Spacer()
            Button {
                openQuickCapture()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .lisdoMenuBarNoFocusRing()
            .help("Quick capture")

            Button {
                openMainWindow()
            } label: {
                Image(systemName: "macwindow")
            }
            .buttonStyle(.borderless)
            .lisdoMenuBarNoFocusRing()
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
                .lisdoMenuBarNoFocusRing()
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
                .lisdoMenuBarNoFocusRing()
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
                .lisdoMenuBarNoFocusRing()
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
                    .lisdoMenuBarNoFocusRing()
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
                    .buttonStyle(.borderless)
                    .lisdoMenuBarNoFocusRing()
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
        Button {
            openFromIPhoneQueue()
        } label: {
            HStack(spacing: 10) {
                Text("Mac processing queue")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text("\(pendingCaptures.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(pendingCaptures.isEmpty ? .secondary : LisdoMacTheme.onAccent)
                    .frame(width: 28, height: 28)
                    .background(pendingCaptures.isEmpty ? LisdoMacTheme.surface2 : LisdoMacTheme.ink1, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(LisdoMacTheme.divider.opacity(0.68))
                    }
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .lisdoMenuBarNoFocusRing()
        .help("Open the iPhone processing queue")
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
                        Button {
                            toggleTodoCompletion(todo)
                        } label: {
                            Image(systemName: todo.status == .completed ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(.secondary)
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .lisdoMenuBarNoFocusRing()
                        .accessibilityLabel(todo.status == .completed ? "Reopen todo" : "Complete todo")

                        Button {
                            openTodo(todo)
                        } label: {
                            HStack(spacing: 8) {
                                Text(todo.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                if let dueDateText = todo.dueDateText {
                                    Text(dueDateText)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .lisdoMenuBarNoFocusRing()
                    }
                }
            }
        }
        .padding(14)
    }

    private var quitRow: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            HStack {
                Text("Quit Lisdo")
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .lisdoMenuBarNoFocusRing()
        .help("Quit Lisdo")
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
            message: "\(LisdoMacMVP2Processing.providerModeLabel(modelContext: modelContext)) is organizing this capture. It will need review before it can become a todo.",
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
                providerMode: LisdoMacMVP2Processing.providerMode(modelContext: modelContext),
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

    private func openQuickCapture() {
        openMainWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NotificationCenter.default.post(name: LisdoMacNotifications.openCapture, object: nil)
        }
    }

    private func openFromIPhoneQueue() {
        openMainWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NotificationCenter.default.post(name: LisdoMacNotifications.openFromIPhone, object: nil)
        }
    }

    private func openTodo(_ todo: Todo) {
        openMainWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NotificationCenter.default.post(
                name: LisdoMacNotifications.openTodo,
                object: nil,
                userInfo: [LisdoMacNotifications.todoIdUserInfoKey: todo.id]
            )
        }
    }

    private func toggleTodoCompletion(_ todo: Todo) {
        CaptureBatchActions.toggleSavedTodoCompletion(todo)
        do {
            try modelContext.save()
            Task { @MainActor in
                await LisdoReminderNotificationScheduler.syncNotifications(for: todo)
            }
        } catch {
            setStatus(
                title: "Could not update todo",
                message: error.localizedDescription,
                tone: .failure
            )
        }
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

    private var syncedSettingsSnapshot: String {
        guard let settings = syncedSettings.first else {
            return "missing"
        }

        return [
            settings.selectedProviderMode.rawValue,
            settings.imageProcessingModeRawValue,
            String(settings.updatedAt.timeIntervalSinceReferenceDate)
        ].joined(separator: "|")
    }

    private func loadSyncedSettings() {
        do {
            let settings = try LisdoMacMVP2Processing.syncedSettings(modelContext: modelContext)
            selectedProviderMode = settings.selectedProviderMode
            imageProcessingModeRawValue = settings.imageProcessingModeRawValue
        } catch {
            selectedProviderMode = LisdoMacMVP2Processing.providerMode(modelContext: modelContext)
            imageProcessingModeRawValue = LisdoMacMVP2Processing.imageProcessingMode(modelContext: modelContext).rawValue
        }
    }

    private var imageProcessingMode: LisdoImageProcessingMode {
        LisdoImageProcessingMode(rawValue: imageProcessingModeRawValue) ?? .visionOCR
    }
}

private struct LisdoMenuBarGlassWindowBackground: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .containerBackground(.regularMaterial, for: .window)
        } else {
            content
                .background(.regularMaterial)
        }
    }
}

private extension View {
    func lisdoMenuBarNoFocusRing() -> some View {
        focusable(false)
            .focusEffectDisabled()
    }
}

struct LisdoLogoMark: View {
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Image("LisdoLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
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
