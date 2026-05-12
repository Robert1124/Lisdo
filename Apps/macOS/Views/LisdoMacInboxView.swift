import AppKit
import LisdoCore
import SwiftData
import SwiftUI

struct LisdoInboxTriageView: View {
    @Environment(\.modelContext) private var modelContext
    let title: String
    let subtitle: String
    let drafts: [ProcessingDraft]
    let captures: [CaptureItem]
    let todos: [Todo]
    let categories: [Category]

    @State private var editingDraft: ProcessingDraft?
    @State private var editingTodo: Todo?
    @State private var errorMessage: String?
    @State private var queueStatus: String?
    @State private var isProcessingQueue = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LisdoSectionHeader(title, subtitle: subtitle) {
                    HStack(spacing: 8) {
                        LisdoChip(title: "\(drafts.count) drafts", systemImage: "sparkles")
                        LisdoChip(title: "\(pendingCaptures.count) pending", systemImage: "icloud")
                        LisdoChip(title: "\(savedTodos.count) saved", systemImage: "tray")
                    }
                }

                if drafts.isEmpty && pendingCaptures.isEmpty && savedTodos.isEmpty {
                    LisdoEmptyState(
                        systemImage: "tray",
                        title: "Nothing needs review",
                        message: "Captured text, OCR results, provider output, and saved inbox todos will appear here."
                    )
                }

                if !drafts.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ready to review")
                            .font(.headline)
                        ForEach(drafts, id: \.id) { draft in
                            LisdoExpandableDraftCard(
                                draft: draft,
                                category: categories.category(id: draft.recommendedCategoryId),
                                capture: captures.first { $0.id == draft.captureItemId },
                                onSave: { approveDraft(draft) },
                                onEdit: { editingDraft = draft },
                                onRevise: { editingDraft = draft },
                                onDelete: { deleteDraft(draft) }
                            )
                        }
                    }
                }

                if !pendingCaptures.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Pending captures")
                                .font(.headline)
                            Spacer()
                            Button {
                                retryFailed()
                            } label: {
                                Label("Retry Failed", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .disabled(failedCaptures.isEmpty || isProcessingQueue)

                            Button {
                                Task {
                                    await processAll()
                                }
                            } label: {
                                Label(isProcessingQueue ? "Processing" : "Process All", systemImage: "sparkles")
                            }
                            .lisdoProcessAllButtonStyle()
                            .disabled(processableCaptures.isEmpty || isProcessingQueue)
                        }

                        if let queueStatus {
                            Text(queueStatus)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
                        }

                        ForEach(pendingCaptures, id: \.id) { capture in
                            LisdoPendingCaptureRow(
                                capture: capture,
                                onRetry: capture.status == .failed ? {
                                    retry(capture)
                                } : nil,
                                onProcess: processableCaptures.contains(where: { $0.id == capture.id }) ? {
                                    processLater(capture)
                                } : nil,
                                onDelete: CaptureDeletionPolicy.canDeleteCapture(capture) ? {
                                    deleteCapture(capture)
                                } : nil
                            )
                        }
                    }
                }

                if !savedTodos.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Saved")
                            .font(.headline)
                        ForEach(savedTodos, id: \.id) { todo in
                            LisdoExpandableTodoCard(
                                todo: todo,
                                category: categories.category(id: todo.categoryId),
                                onToggleCompletion: { toggleCompletion(todo) },
                                onToggleBlock: { block in toggleBlock(block, in: todo) },
                                onEdit: { editingTodo = todo },
                                onDelete: { deleteTodo(todo) }
                            )
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(LisdoMacTheme.surface)
        .sheet(isPresented: Binding(get: { editingDraft != nil }, set: { if !$0 { editingDraft = nil } })) {
            if let draft = editingDraft {
                LisdoDraftReviewSheet(draft: draft, categories: categories)
            }
        }
        .sheet(isPresented: Binding(get: { editingTodo != nil }, set: { if !$0 { editingTodo = nil } })) {
            if let todo = editingTodo {
                LisdoMacTodoEditorSheet(todo: todo, categories: categories)
                    .frame(width: 620, height: 560)
            }
        }
        .alert("Could not save draft", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var processableCaptures: [CaptureItem] {
        CaptureBatchSelector.processablePendingCaptures(from: LisdoMacMVP2Processing.pendingQueue(from: pendingCaptures))
    }

    private var failedCaptures: [CaptureItem] {
        CaptureBatchSelector.failedCaptures(from: LisdoMacMVP2Processing.pendingQueue(from: pendingCaptures))
    }

    private var pendingCaptures: [CaptureItem] {
        captures.filter { capture in
            capture.status == .rawCaptured
            || capture.status == .pendingProcessing
            || capture.status == .processing
            || capture.status == .failed
            || capture.status == .retryPending
        }
    }

    private var savedTodos: [Todo] {
        todos.filter { $0.status == .open || $0.status == .inProgress }
    }

    private func approveDraft(_ draft: ProcessingDraft) {
        do {
            let recommendation = CategoryRecommender.resolveCategory(
                for: draft,
                availableCategories: categories,
                fallbackCategoryId: categories.defaultCategoryId
            )
            let todo = try DraftApprovalConverter.convert(
                draft,
                categoryId: recommendation.categoryId,
                approval: DraftApproval(approvedByUser: true)
            )
            modelContext.insert(todo)

            if let capture = captures.first(where: { $0.id == draft.captureItemId }),
               capture.status == .processedDraft {
                try? capture.transition(to: .approvedTodo)
            }

            modelContext.delete(draft)
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteDraft(_ draft: ProcessingDraft) {
        let captureIds = Set(CaptureDeletionPolicy.captureIdsToDelete(whenDeleting: draft, captures: captures))
        let capturesToDelete = captures.filter { captureIds.contains($0.id) }

        modelContext.delete(draft)
        capturesToDelete.forEach(modelContext.delete)

        do {
            try modelContext.save()
            queueStatus = capturesToDelete.isEmpty
                ? "Deleted draft."
                : "Deleted draft and linked capture."
        } catch {
            errorMessage = "Could not delete draft: \(error.localizedDescription)"
        }
    }

    private func deleteCapture(_ capture: CaptureItem) {
        guard CaptureDeletionPolicy.canDeleteCapture(capture) else {
            queueStatus = "Saved todos cannot be deleted from this queue."
            return
        }

        modelContext.delete(capture)

        do {
            try modelContext.save()
            queueStatus = "Deleted capture."
        } catch {
            errorMessage = "Could not delete capture: \(error.localizedDescription)"
        }
    }

    private func toggleCompletion(_ todo: Todo) {
        CaptureBatchActions.toggleSavedTodoCompletion(todo)

        do {
            try modelContext.save()
            Task { @MainActor in
                await LisdoReminderNotificationScheduler.syncNotifications(for: todo)
            }
            queueStatus = nil
        } catch {
            errorMessage = "Could not update todo: \(error.localizedDescription)"
        }
    }

    private func toggleBlock(_ block: TodoBlock, in todo: Todo) {
        guard block.type == .checkbox else { return }

        block.checked.toggle()
        if todo.status == .completed && !block.checked {
            todo.status = .open
        }
        todo.updatedAt = Date()

        do {
            try modelContext.save()
            queueStatus = nil
        } catch {
            errorMessage = "Could not update checklist item: \(error.localizedDescription)"
        }
    }

    private func deleteTodo(_ todo: Todo) {
        let reminderIDs = (todo.reminders ?? []).map(\.id)
        TodoTrashPolicy.moveToTrash([todo])

        do {
            try modelContext.save()
            Task { await LisdoReminderNotificationScheduler.cancel(reminderIDs: reminderIDs) }
            queueStatus = "Moved todo to Trash."
        } catch {
            errorMessage = "Could not move todo to Trash: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func processAll() async {
        guard !isProcessingQueue else { return }

        isProcessingQueue = true
        queueStatus = "Processing \(processableCaptures.count) captures with the selected provider."
        defer { isProcessingQueue = false }

        let outcome = await LisdoMacMVP2Processing.processAllQueuedCaptures(
            pendingCaptures,
            selectedCategoryId: categories.defaultCategoryId,
            categories: categories,
            modelContext: modelContext
        )
        queueStatus = outcome.message
    }

    @MainActor
    private func process(_ capture: CaptureItem) async {
        guard !isProcessingQueue else { return }

        isProcessingQueue = true
        queueStatus = "Processing one capture with the selected provider."
        defer { isProcessingQueue = false }

        let outcome = await LisdoMacMVP2Processing.processQueuedCapture(
            capture,
            selectedCategoryId: categories.defaultCategoryId,
            categories: categories,
            modelContext: modelContext
        )
        queueStatus = outcome.message
    }

    private func retryFailed() {
        do {
            let retried = try CaptureBatchActions.queueFailedCapturesForRetry(pendingCaptures)
            try modelContext.save()
            queueStatus = "Queued \(retried.count) failed capture\(retried.count == 1 ? "" : "s") for retry."
        } catch {
            queueStatus = "Could not queue failed captures: \(error.localizedDescription)"
        }
    }

    private func retry(_ capture: CaptureItem) {
        let outcome = LisdoMacMVP2Processing.retryCapture(capture, modelContext: modelContext)
        queueStatus = outcome.message
    }

    private func processLater(_ capture: CaptureItem) {
        let task: Task<Void, Never> = Task {
            await process(capture)
        }
        _ = task
    }
}

struct LisdoExpandableDraftCard: View {
    let draft: ProcessingDraft
    let category: Category?
    let capture: CaptureItem?
    var onSave: (() -> Void)?
    var onEdit: (() -> Void)?
    var onRevise: (() -> Void)?
    var onDelete: (() -> Void)?

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                LisdoDraftCard(
                    draft: draft,
                    category: category,
                    capture: capture,
                    onSave: onSave,
                    onEdit: onEdit,
                    onRevise: onRevise,
                    onDelete: onDelete
                )
                .transition(.opacity)
            } else {
                LisdoCompactDraftRow(
                    draft: draft,
                    category: category,
                    capture: capture,
                    onSave: onSave,
                    onDelete: onDelete,
                    onOpen: {
                        withAnimation(.snappy(duration: 0.22)) {
                            isExpanded = true
                        }
                    }
                )
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct LisdoCompactDraftRow: View {
    let draft: ProcessingDraft
    let category: Category?
    let capture: CaptureItem?
    var onSave: (() -> Void)?
    var onDelete: (() -> Void)?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                LisdoCategoryDot(category: category)
                Text(draft.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                LisdoChip(title: "Draft", systemImage: "sparkles")
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(LisdoMacTheme.ink7, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(LisdoMacTheme.ink4.opacity(0.48))
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onSave {
                Button {
                    onSave()
                } label: {
                    Label("Save Draft", systemImage: "checkmark")
                }
            }
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Draft", systemImage: "trash")
                }
            }
        }
    }
}

struct LisdoDraftCard: View {
    let draft: ProcessingDraft
    let category: Category?
    let capture: CaptureItem?
    var onSave: (() -> Void)?
    var onEdit: (() -> Void)?
    var onRevise: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    LisdoChip(title: sourceLabel, systemImage: sourceImage)
                    Text(capturedLabel)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                LisdoChip(title: "Draft", systemImage: "sparkles", isDark: false)
            }

            HStack(spacing: 8) {
                LisdoCategoryDot(category: category)
                Text("\(category?.name ?? "Inbox") suggested")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                if let confidence = draft.confidence {
                    Text("\(Int(confidence * 100))%")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(draft.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let summary = draft.summary {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !draft.blocks.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(draft.blocks.sorted(by: { $0.order < $1.order }), id: \.self) { block in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .stroke(style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                                .foregroundStyle(.secondary.opacity(0.55))
                                .frame(width: 14, height: 14)
                                .padding(.top, 2)
                            Text(block.content)
                                .font(.callout)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }

            if draft.needsClarification && !draft.questionsForUser.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Needs clarification")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(draft.questionsForUser, id: \.self) { question in
                        Text(question)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 10))
            }

            if onSave != nil || onEdit != nil || onRevise != nil {
                HStack(spacing: 8) {
                    if let onSave {
                        Button {
                            onSave()
                        } label: {
                            Label("Save", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if let onEdit {
                        Button("Edit", action: onEdit)
                            .buttonStyle(.bordered)
                    }

                    if let onRevise {
                        Button {
                            onRevise()
                        } label: {
                            Label("Revise", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderless)
                    }

                    Spacer()

                    if let onDelete {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(16)
        .background(LisdoMacTheme.ink7, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .foregroundStyle(LisdoMacTheme.ink4.opacity(0.55))
        }
        .contextMenu {
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Draft", systemImage: "trash")
                }
            }
        }
    }

    private var sourceImage: String {
        switch capture?.sourceType {
        case .voiceNote:
            return "waveform"
        case .photoImport, .screenshotImport, .cameraImport, .macScreenRegion:
            return "photo"
        case .shareExtension:
            return "square.and.arrow.down"
        case .clipboard:
            return "doc.on.clipboard"
        default:
            return "text.alignleft"
        }
    }

    private var sourceLabel: String {
        switch capture?.sourceType {
        case .textPaste:
            return "Pasted text"
        case .clipboard:
            return "Clipboard"
        case .macScreenRegion:
            return "Screen region"
        case .screenshotImport:
            return "Screenshot"
        case .photoImport:
            return "Image"
        case .cameraImport:
            return "Camera"
        case .shareExtension:
            return "Share"
        case .voiceNote:
            return "Voice"
        case nil:
            return "Captured"
        }
    }

    private var capturedLabel: String {
        guard let capture else { return "Draft" }
        return capture.createdAt.formatted(.relative(presentation: .named))
    }
}

struct LisdoPendingCaptureRow: View {
    let capture: CaptureItem
    var onRetry: (() -> Void)?
    var onProcess: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 28, height: 28)
                .background(LisdoMacTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(LisdoMacTheme.divider.opacity(0.72))
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(preview)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: statusImage)
                    Text(statusTitle)
                    Text("·")
                    Text(statusMessage)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text(capture.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if capture.status == .failed, let onRetry {
                    Button {
                        onRetry()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if let onProcess {
                    Button {
                        onProcess()
                    } label: {
                        Label("Process", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(LisdoMacTheme.divider.opacity(0.72))
        }
        .contextMenu {
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Capture", systemImage: "trash")
                }
            }
        }
    }

    private var preview: String {
        let text = capture.sourceText ?? capture.transcriptText ?? capture.userNote ?? capture.sourceImageAssetId
        return text?.lisdoTrimmed.isEmpty == false ? text!.lisdoTrimmed : "Captured item"
    }

    private var icon: String {
        switch capture.sourceType {
        case .voiceNote:
            return "waveform"
        case .photoImport, .screenshotImport, .cameraImport, .macScreenRegion:
            return "photo"
        case .shareExtension:
            return "square.and.arrow.down"
        case .clipboard:
            return "doc.on.clipboard"
        case .textPaste:
            return "text.alignleft"
        }
    }

    private var statusImage: String {
        switch capture.status {
        case .failed:
            return "exclamationmark.triangle"
        case .processing:
            return "sparkles"
        case .retryPending:
            return "arrow.clockwise"
        default:
            return "icloud"
        }
    }

    private var statusTitle: String {
        switch capture.status {
        case .rawCaptured:
            return "Captured"
        case .pendingProcessing:
            return "Waiting for processing"
        case .processing:
            return "Processing on Mac"
        case .processedDraft:
            return "Ready to review"
        case .approvedTodo:
            return "Saved"
        case .failed:
            return "Failed"
        case .retryPending:
            return "Retry pending"
        }
    }

    private var statusMessage: String {
        switch capture.status {
        case .pendingProcessing:
            return "Will become a draft after provider processing."
        case .processing:
            return "Organizing captured text into a draft."
        case .failed:
            return capture.processingError ?? "Review provider setup before retrying."
        case .retryPending:
            return "Queued to retry when processing is available."
        default:
            return "AI output is draft-first and needs review."
        }
    }
}

struct LisdoExpandableTodoCard: View {
    let todo: Todo
    let category: Category?
    var onToggleCompletion: (() -> Void)?
    var onToggleBlock: ((TodoBlock) -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                LisdoTodoCard(
                    todo: todo,
                    category: category,
                    onToggleCompletion: onToggleCompletion,
                    onToggleBlock: onToggleBlock,
                    onEdit: onEdit,
                    onDelete: onDelete,
                    onCollapse: {
                        withAnimation(.snappy(duration: 0.22)) {
                            isExpanded = false
                        }
                    }
                )
                .transition(.opacity)
            } else {
                LisdoCompactTodoRow(
                    todo: todo,
                    category: category,
                    onOpen: {
                        withAnimation(.snappy(duration: 0.22)) {
                            isExpanded = true
                        }
                    },
                    onToggleCompletion: onToggleCompletion,
                    onEdit: onEdit,
                    onDelete: onDelete
                )
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct LisdoCompactTodoRow: View {
    let todo: Todo
    let category: Category?
    let onOpen: () -> Void
    var onToggleCompletion: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                onToggleCompletion?()
            } label: {
                Image(systemName: todo.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.status == .completed ? .secondary : .primary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()
            .disabled(onToggleCompletion == nil)
            .accessibilityLabel(todo.status == .completed ? "Reopen todo" : "Complete todo")

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        LisdoCategoryDot(category: category)
                        Text(category?.name ?? "Inbox")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        if let dateLabel {
                            Text("· \(dateLabel)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    Text(todo.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let summary = todo.summary?.lisdoTrimmed, !summary.isEmpty {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 10)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onOpen()
            }
        }
        .padding(14)
        .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(LisdoMacTheme.divider.opacity(0.72))
        }
        .contextMenu {
            if let onToggleCompletion {
                Button {
                    onToggleCompletion()
                } label: {
                    Label(todo.status == .completed ? "Reopen Todo" : "Complete Todo", systemImage: todo.status == .completed ? "circle" : "checkmark.circle")
                }
            }
            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Edit Todo", systemImage: "pencil")
                }
            }
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Todo", systemImage: "trash")
                }
            }
        }
    }

    private var dateLabel: String? {
        if let scheduledDate = todo.scheduledDate {
            return "Scheduled \(scheduledDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
        }
        if let dueDate = todo.dueDate {
            return "Due \(dueDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
        }
        if let dueDateText = todo.dueDateText?.lisdoTrimmed, !dueDateText.isEmpty {
            return "Due \(dueDateText)"
        }
        return nil
    }
}

struct LisdoTodoCard: View {
    let todo: Todo
    let category: Category?
    var onToggleCompletion: (() -> Void)?
    var onToggleBlock: ((TodoBlock) -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?
    var onCollapse: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                onToggleCompletion?()
            } label: {
                Image(systemName: todo.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.status == .completed ? .secondary : .primary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()
            .disabled(onToggleCompletion == nil)
            .accessibilityLabel(todo.status == .completed ? "Reopen todo" : "Complete todo")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    LisdoCategoryDot(category: category)
                    Text(category?.name ?? "Inbox")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    if let dueDateText = todo.dueDateText {
                        Text("· \(dueDateText)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(todo.title)
                    .font(.headline)
                if let summary = todo.summary {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                let reminders = todo.reminders?.sortedForMacReminderDisplay() ?? []
                if !reminders.isEmpty {
                    LisdoTodoReminderList(reminders: reminders)
                        .padding(.top, 2)
                }

                let blocks = todo.blocks ?? []
                if !blocks.isEmpty {
                    LisdoMacTodoBlockList(blocks: blocks.sortedForMacTodoDisplay(), onToggleBlock: onToggleBlock)
                        .padding(.top, 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onCollapse?()
            }
            Spacer()

            if onEdit != nil || onDelete != nil {
                HStack(alignment: .center, spacing: 4) {
                    if let onEdit {
                        LisdoMacIconActionButton(
                            systemName: "pencil",
                            accessibilityLabel: "Edit todo",
                            action: onEdit
                        )
                    }

                    if let onDelete {
                        LisdoMacIconActionButton(
                            systemName: "trash",
                            accessibilityLabel: "Delete todo",
                            role: .destructive,
                            action: onDelete
                        )
                    }
                }
                .frame(height: 28, alignment: .center)
            }
        }
        .padding(16)
        .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(LisdoMacTheme.divider.opacity(0.72))
        }
        .contextMenu {
            if let onToggleCompletion {
                Button {
                    onToggleCompletion()
                } label: {
                    Label(todo.status == .completed ? "Reopen Todo" : "Complete Todo", systemImage: todo.status == .completed ? "circle" : "checkmark.circle")
                }
            }

            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Edit Todo", systemImage: "pencil")
                }
            }

            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Todo", systemImage: "trash")
                }
            }
        }
    }
}

private struct LisdoMacIconActionButton: View {
    let systemName: String
    let accessibilityLabel: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role) {
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .regular))
                .imageScale(.medium)
                .frame(width: 28, height: 28, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .focusable(false)
        .focusEffectDisabled()
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct LisdoMacTodoBlockList: View {
    let blocks: [TodoBlock]
    var onToggleBlock: ((TodoBlock) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(blocks, id: \.id) { block in
                LisdoMacTodoBlockRow(block: block, onToggle: onToggleBlock)
            }
        }
    }
}

private struct LisdoMacTodoBlockRow: View {
    let block: TodoBlock
    var onToggle: ((TodoBlock) -> Void)?

    var body: some View {
        switch block.type {
        case .checkbox:
            Button {
                onToggle?(block)
            } label: {
                rowLabel {
                    Image(systemName: block.checked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()
            .disabled(onToggle == nil)
            .accessibilityLabel(block.checked ? "Reopen checklist item" : "Complete checklist item")
        case .bullet:
            rowLabel {
                Circle()
                    .fill(.secondary)
                    .frame(width: 5, height: 5)
                    .frame(width: 16)
            }
        case .note:
            rowLabel {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rowLabel<Icon: View>(@ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 8) {
            icon()
                .frame(width: 16)
            Text(block.content)
                .foregroundStyle(block.type == .checkbox && block.checked ? .secondary : .primary)
                .strikethrough(block.type == .checkbox && block.checked, color: .secondary)
        }
        .font(.callout)
        .contentShape(Rectangle())
    }
}

private struct LisdoTodoReminderList: View {
    let reminders: [TodoReminder]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "bell")
                Text("Reminders")
                    .textCase(.uppercase)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            ForEach(reminders, id: \.id) { reminder in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "bell")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(reminder.title)
                            .foregroundStyle(reminder.isCompleted ? .secondary : .primary)
                        if let detail = reminderDetail(reminder) {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(.callout)
            }
        }
        .padding(10)
        .background(LisdoMacTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(LisdoMacTheme.divider.opacity(0.78))
        }
    }

    private func reminderDetail(_ reminder: TodoReminder) -> String? {
        [reminder.reminderDateText, concreteReminderDateLabel(reminder.reminderDate), reminder.reason]
            .compactMap { value in
                guard let trimmed = value?.lisdoTrimmed, !trimmed.isEmpty else {
                    return nil
                }
                return trimmed
            }
            .joined(separator: " · ")
            .lisdoTrimmed
            .nilIfEmptyForReminderDisplay
    }

    private func concreteReminderDateLabel(_ date: Date?) -> String? {
        date?.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}

struct LisdoTodayView: View {
    @Environment(\.modelContext) private var modelContext

    let todos: [Todo]
    let categories: [Category]
    @State private var todoStatus: String?
    @State private var editingTodo: Todo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LisdoSectionHeader("Today", subtitle: "Saved todos due or scheduled today.")
                if let todoStatus {
                    Text(todoStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
                }
                if todos.isEmpty {
                    LisdoEmptyState(
                        systemImage: "clock",
                        title: "No saved todos for today",
                        message: "Approved todos with a due date or scheduled date for today will appear here. Drafts remain in review until you save them."
                    )
                } else {
                    ForEach(todos, id: \.id) { todo in
                        LisdoTodoCard(
                            todo: todo,
                            category: categories.category(id: todo.categoryId),
                            onToggleCompletion: { toggleCompletion(todo) },
                            onToggleBlock: { block in toggleBlock(block, in: todo) },
                            onEdit: { editingTodo = todo },
                            onDelete: { deleteTodo(todo) }
                        )
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(LisdoMacTheme.surface)
        .sheet(isPresented: Binding(get: { editingTodo != nil }, set: { if !$0 { editingTodo = nil } })) {
            if let todo = editingTodo {
                LisdoMacTodoEditorSheet(todo: todo, categories: categories)
                    .frame(width: 620, height: 560)
            }
        }
    }

    private func toggleCompletion(_ todo: Todo) {
        CaptureBatchActions.toggleSavedTodoCompletion(todo)

        do {
            try modelContext.save()
            Task { @MainActor in
                await LisdoReminderNotificationScheduler.syncNotifications(for: todo)
            }
            todoStatus = nil
        } catch {
            todoStatus = "Could not update todo: \(error.localizedDescription)"
        }
    }

    private func toggleBlock(_ block: TodoBlock, in todo: Todo) {
        guard block.type == .checkbox else { return }

        block.checked.toggle()
        if todo.status == .completed && !block.checked {
            todo.status = .open
        }
        todo.updatedAt = Date()

        do {
            try modelContext.save()
            todoStatus = nil
        } catch {
            todoStatus = "Could not update checklist item: \(error.localizedDescription)"
        }
    }

    private func deleteTodo(_ todo: Todo) {
        let reminderIDs = (todo.reminders ?? []).map(\.id)
        TodoTrashPolicy.moveToTrash([todo])

        do {
            try modelContext.save()
            Task { await LisdoReminderNotificationScheduler.cancel(reminderIDs: reminderIDs) }
            todoStatus = "Moved todo to Trash."
        } catch {
            todoStatus = "Could not move todo to Trash: \(error.localizedDescription)"
        }
    }
}

struct LisdoMacTodoCollectionView: View {
    @Environment(\.modelContext) private var modelContext

    let title: String
    let subtitle: String
    let emptySystemImage: String
    let emptyTitle: String
    let emptyMessage: String
    let todos: [Todo]
    let categories: [Category]
    let focusedTodoId: UUID?
    var allowsCompletionToggle = true
    var allowsDelete = true

    @State private var todoStatus: String?
    @State private var editingTodo: Todo?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LisdoSectionHeader(title, subtitle: subtitle)

                    if let todoStatus {
                        Text(todoStatus)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
                    }

                    if todos.isEmpty {
                        LisdoEmptyState(
                            systemImage: emptySystemImage,
                            title: emptyTitle,
                            message: emptyMessage
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(todos, id: \.id) { todo in
                                LisdoExpandableTodoCard(
                                    todo: todo,
                                    category: categories.category(id: todo.categoryId),
                                    onToggleCompletion: allowsCompletionToggle ? { toggleCompletion(todo) } : nil,
                                    onToggleBlock: allowsCompletionToggle ? { block in toggleBlock(block, in: todo) } : nil,
                                    onEdit: { editingTodo = todo },
                                    onDelete: allowsDelete ? { moveTodoToTrash(todo) } : nil
                                )
                                .id(todo.id)
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                scrollToFocusedTodo(with: proxy)
            }
            .onChange(of: focusedTodoId) { _, _ in
                scrollToFocusedTodo(with: proxy)
            }
        }
        .background(LisdoMacTheme.surface)
        .sheet(isPresented: Binding(get: { editingTodo != nil }, set: { if !$0 { editingTodo = nil } })) {
            if let todo = editingTodo {
                LisdoMacTodoEditorSheet(todo: todo, categories: categories)
                    .frame(width: 620, height: 560)
            }
        }
    }

    private func scrollToFocusedTodo(with proxy: ScrollViewProxy) {
        guard let focusedTodoId,
              todos.contains(where: { $0.id == focusedTodoId })
        else {
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            withAnimation(.snappy(duration: 0.24)) {
                proxy.scrollTo(focusedTodoId, anchor: .center)
            }
        }
    }

    private func toggleCompletion(_ todo: Todo) {
        CaptureBatchActions.toggleSavedTodoCompletion(todo)

        do {
            try modelContext.save()
            Task { @MainActor in
                await LisdoReminderNotificationScheduler.syncNotifications(for: todo)
            }
            todoStatus = nil
        } catch {
            todoStatus = "Could not update todo: \(error.localizedDescription)"
        }
    }

    private func toggleBlock(_ block: TodoBlock, in todo: Todo) {
        guard block.type == .checkbox else { return }

        block.checked.toggle()
        if todo.status == .completed && !block.checked {
            todo.status = .open
        }
        todo.updatedAt = Date()

        do {
            try modelContext.save()
            todoStatus = nil
        } catch {
            todoStatus = "Could not update checklist item: \(error.localizedDescription)"
        }
    }

    private func moveTodoToTrash(_ todo: Todo) {
        let reminderIDs = (todo.reminders ?? []).map(\.id)
        TodoTrashPolicy.moveToTrash([todo])

        do {
            try modelContext.save()
            Task { await LisdoReminderNotificationScheduler.cancel(reminderIDs: reminderIDs) }
            todoStatus = "Moved todo to Trash."
        } catch {
            todoStatus = "Could not move todo to Trash: \(error.localizedDescription)"
        }
    }
}

struct LisdoCategoryDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let category: Category?
    let todos: [Todo]
    let drafts: [ProcessingDraft]
    let categories: [Category]
    let focusedTodoId: UUID?
    @State private var showsCategoryEditor = false
    @State private var todoStatus: String?
    @State private var editingTodo: Todo?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LisdoSectionHeader(
                        category?.name ?? "Category",
                        subtitle: category?.descriptionText ?? "Saved todos and suggested drafts for this category."
                    ) {
                        if category != nil {
                            Button {
                                showsCategoryEditor = true
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.callout.weight(.semibold))
                                    .frame(width: 32, height: 32)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .lisdoGlassSurface(cornerRadius: 16, interactive: true)
                            .focusable(false)
                            .help("Edit Category")
                        }
                    }

                    if let todoStatus {
                        Text(todoStatus)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
                    }

                    if todos.isEmpty && drafts.isEmpty {
                        LisdoEmptyState(
                            systemImage: category?.icon ?? "folder",
                            title: "No items in this category",
                            message: "Approved todos will collect here. Drafts only appear as suggestions until you review and save them."
                        )
                    }

                    if !drafts.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Suggested drafts")
                                .font(.headline)
                            ForEach(drafts, id: \.id) { draft in
                                LisdoExpandableDraftCard(
                                    draft: draft,
                                    category: category,
                                    capture: nil,
                                    onSave: nil,
                                    onEdit: nil,
                                    onRevise: nil
                                )
                            }
                        }
                    }

                    if !todos.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Saved")
                                .font(.headline)
                            ForEach(todos, id: \.id) { todo in
                                LisdoExpandableTodoCard(
                                    todo: todo,
                                    category: categories.category(id: todo.categoryId),
                                    onToggleCompletion: { toggleCompletion(todo) },
                                    onToggleBlock: { block in toggleBlock(block, in: todo) },
                                    onEdit: { editingTodo = todo },
                                    onDelete: { deleteTodo(todo) }
                                )
                                .id(todo.id)
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                scrollToFocusedTodo(with: proxy)
            }
            .onChange(of: focusedTodoId) { _, _ in
                scrollToFocusedTodo(with: proxy)
            }
        }
        .background(LisdoMacTheme.surface)
        .sheet(isPresented: $showsCategoryEditor) {
            LisdoMacCategoryEditorSheet(category: category)
                .frame(minWidth: 520, minHeight: 520)
        }
        .sheet(isPresented: Binding(get: { editingTodo != nil }, set: { if !$0 { editingTodo = nil } })) {
            if let todo = editingTodo {
                LisdoMacTodoEditorSheet(todo: todo, categories: categories)
                    .frame(width: 620, height: 560)
            }
        }
    }

    private func scrollToFocusedTodo(with proxy: ScrollViewProxy) {
        guard let focusedTodoId,
              todos.contains(where: { $0.id == focusedTodoId })
        else {
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            withAnimation(.snappy(duration: 0.24)) {
                proxy.scrollTo(focusedTodoId, anchor: .center)
            }
        }
    }

    private func toggleCompletion(_ todo: Todo) {
        CaptureBatchActions.toggleSavedTodoCompletion(todo)

        do {
            try modelContext.save()
            Task { @MainActor in
                await LisdoReminderNotificationScheduler.syncNotifications(for: todo)
            }
            todoStatus = nil
        } catch {
            todoStatus = "Could not update todo: \(error.localizedDescription)"
        }
    }

    private func toggleBlock(_ block: TodoBlock, in todo: Todo) {
        guard block.type == .checkbox else { return }

        block.checked.toggle()
        if todo.status == .completed && !block.checked {
            todo.status = .open
        }
        todo.updatedAt = Date()

        do {
            try modelContext.save()
            todoStatus = nil
        } catch {
            todoStatus = "Could not update checklist item: \(error.localizedDescription)"
        }
    }

    private func deleteTodo(_ todo: Todo) {
        let reminderIDs = (todo.reminders ?? []).map(\.id)
        TodoTrashPolicy.moveToTrash([todo])

        do {
            try modelContext.save()
            Task { await LisdoReminderNotificationScheduler.cancel(reminderIDs: reminderIDs) }
            todoStatus = "Moved todo to Trash."
        } catch {
            todoStatus = "Could not move todo to Trash: \(error.localizedDescription)"
        }
    }
}

struct LisdoMacCategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Todo.updatedAt, order: .reverse) private var todos: [Todo]
    @Query(sort: \ProcessingDraft.generatedAt, order: .reverse) private var drafts: [ProcessingDraft]

    let category: Category?

    @State private var name: String
    @State private var descriptionText: String
    @State private var formattingInstruction: String
    @State private var schemaPreset: CategorySchemaPreset
    @State private var icon: String
    @State private var usesCustomIcon: Bool
    @State private var errorMessage: String?
    @State private var showsDeleteConfirmation = false

    init(category: Category?) {
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        _descriptionText = State(initialValue: category?.descriptionText ?? "")
        _formattingInstruction = State(initialValue: category?.formattingInstruction ?? "")
        _schemaPreset = State(initialValue: category?.schemaPreset ?? .general)
        let initialIcon = category?.icon ?? "folder"
        _icon = State(initialValue: initialIcon)
        _usesCustomIcon = State(initialValue: !Self.commonIcons.contains(initialIcon))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(category == nil ? "New category" : "Edit category")
                        .font(.headline)
                    Text("Category prompt and schema settings guide future drafts. They do not approve todos.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
            }
            .padding(18)

            Divider()

            Form {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                iconChooser
                Picker("Schema preset", selection: $schemaPreset) {
                    ForEach(CategorySchemaPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                Text(schemaPreset.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.callout.weight(.medium))
                    Text("Shown to you in the sidebar and category views so the category is easy to recognize.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $descriptionText)
                        .frame(minHeight: 82)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Instruction")
                        .font(.callout.weight(.medium))
                    Text("Sent to the selected provider as category-specific guidance when Lisdo creates or revises a draft.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $formattingInstruction)
                        .frame(minHeight: 110)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 10))
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding(18)

            Divider()

            HStack {
                if category != nil {
                    Button("Delete Category", role: .destructive) {
                        requestDelete()
                    }
                    .disabled(isInboxFallbackCategory)
                    .help(isInboxFallbackCategory ? "Inbox is the fallback category and cannot be deleted." : "Delete this category")
                }

                Spacer()
                Button("Save Category") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.lisdoTrimmed.isEmpty)
            }
            .padding(18)
        }
        .confirmationDialog(
            "Delete category?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move Items to Inbox and Delete", role: .destructive) {
                deleteCategory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteConfirmationMessage)
        }
    }

    private var iconChooser: some View {
        DisclosureGroup("Icon") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: validIconName ?? "questionmark.square.dashed")
                        .frame(width: 24, height: 24)
                    Text(validIconName ?? "Invalid symbol")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 8)], spacing: 8) {
                    ForEach(Self.commonIcons, id: \.self) { symbol in
                        Button {
                            icon = symbol
                            usesCustomIcon = false
                            errorMessage = nil
                        } label: {
                            Image(systemName: symbol)
                                .frame(width: 26, height: 26)
                                .padding(4)
                                .background(icon == symbol && !usesCustomIcon ? LisdoMacTheme.info.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .help(symbol)
                    }
                }

                Button {
                    usesCustomIcon.toggle()
                    if usesCustomIcon && icon.lisdoTrimmed.isEmpty {
                        icon = "folder"
                    }
                } label: {
                    Label("Customize", systemImage: "keyboard")
                }
                .buttonStyle(.borderless)

                if usesCustomIcon {
                    TextField("Custom SF Symbol name", text: $icon)
                        .textFieldStyle(.roundedBorder)
                    if let iconValidationError {
                        Text(iconValidationError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private var validIconName: String? {
        let trimmed = icon.lisdoTrimmed
        guard !trimmed.isEmpty else { return nil }
        return Self.isValidSystemSymbol(trimmed) ? trimmed : nil
    }

    private var iconValidationError: String? {
        let trimmed = icon.lisdoTrimmed
        guard !trimmed.isEmpty else { return nil }
        return Self.isValidSystemSymbol(trimmed) ? nil : "This SF Symbol name is not available on this system."
    }

    private var isInboxFallbackCategory: Bool {
        category?.id == DefaultCategorySeeder.inboxCategoryId
    }

    private var referencedTodos: [Todo] {
        guard let category else { return [] }
        return todos.filter { $0.categoryId == category.id }
    }

    private var referencedDrafts: [ProcessingDraft] {
        guard let category else { return [] }
        return drafts.filter { $0.recommendedCategoryId == category.id }
    }

    private var referencedItemCount: Int {
        referencedTodos.count + referencedDrafts.count
    }

    private var deleteConfirmationMessage: String {
        "This category is used by \(referencedTodos.count) todos and \(referencedDrafts.count) drafts. They will be moved to Inbox before the category is deleted."
    }

    private func save() {
        do {
            guard iconValidationError == nil else {
                errorMessage = iconValidationError
                return
            }

            if let category {
                category.name = name.lisdoTrimmed
                category.descriptionText = descriptionText.lisdoTrimmed
                category.formattingInstruction = formattingInstruction.lisdoTrimmed
                category.schemaPreset = schemaPreset
                category.icon = icon.lisdoTrimmed.isEmpty ? nil : icon.lisdoTrimmed
                category.updatedAt = Date()
            } else {
                let category = Category(
                    name: name.lisdoTrimmed,
                    descriptionText: descriptionText.lisdoTrimmed,
                    formattingInstruction: formattingInstruction.lisdoTrimmed,
                    schemaPreset: schemaPreset,
                    icon: icon.lisdoTrimmed.isEmpty ? nil : icon.lisdoTrimmed
                )
                modelContext.insert(category)
            }
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Could not save category: \(error.localizedDescription)"
        }
    }

    private func requestDelete() {
        guard category != nil else { return }
        guard !isInboxFallbackCategory else {
            errorMessage = "Inbox is the fallback category and cannot be deleted."
            return
        }

        if referencedItemCount > 0 {
            showsDeleteConfirmation = true
        } else {
            deleteCategory()
        }
    }

    private func deleteCategory() {
        guard let category else { return }
        guard !isInboxFallbackCategory else {
            errorMessage = "Inbox is the fallback category and cannot be deleted."
            return
        }

        do {
            let inboxCategoryId = DefaultCategorySeeder.inboxCategoryId
            let now = Date()

            for todo in referencedTodos {
                todo.categoryId = inboxCategoryId
                todo.updatedAt = now
            }

            for draft in referencedDrafts {
                draft.recommendedCategoryId = inboxCategoryId
            }

            modelContext.delete(category)
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Could not delete category: \(error.localizedDescription)"
        }
    }

    private static let commonIcons = [
        "folder", "tray", "briefcase", "book", "graduationcap", "cart", "bag",
        "person", "house", "calendar", "bell", "doc.text", "list.bullet",
        "checklist", "lightbulb", "star", "flag", "laptopcomputer", "pencil",
        "hammer", "heart"
    ]

    private static func isValidSystemSymbol(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}

struct LisdoMacTodoEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let todo: Todo
    let categories: [Category]

    @State private var categoryId: String
    @State private var title: String
    @State private var summary: String
    @State private var dueDateText: String
    @State private var dateMode: LisdoMacTodoDateMode
    @State private var selectedDate: Date
    @State private var priority: TodoPriority?
    @State private var blocks: [TodoBlockEditorDraft]
    @State private var reminders: [TodoReminderEditorDraft]
    @State private var errorMessage: String?

    init(todo: Todo, categories: [Category]) {
        self.todo = todo
        self.categories = categories
        _categoryId = State(initialValue: todo.categoryId)
        _title = State(initialValue: todo.title)
        _summary = State(initialValue: todo.summary ?? "")
        _dueDateText = State(initialValue: todo.dueDateText ?? "")
        if let scheduledDate = todo.scheduledDate {
            _dateMode = State(initialValue: .scheduled)
            _selectedDate = State(initialValue: scheduledDate)
        } else if let dueDate = todo.dueDate {
            _dateMode = State(initialValue: .due)
            _selectedDate = State(initialValue: dueDate)
        } else {
            _dateMode = State(initialValue: .none)
            _selectedDate = State(initialValue: Date())
        }
        _priority = State(initialValue: todo.priority)
        _blocks = State(initialValue: (todo.blocks ?? [])
            .sortedForMacTodoDisplay()
            .map { TodoBlockEditorDraft(block: $0) })
        _reminders = State(initialValue: (todo.reminders ?? [])
            .sortedForMacReminderDisplay()
            .map { TodoReminderEditorDraft(reminder: $0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Category", selection: $categoryId) {
                        ForEach(categories, id: \.id) { category in
                            Text(category.name).tag(category.id)
                        }
                        if categories.category(id: categoryId) == nil {
                            Text(categoryId.isEmpty ? "Inbox" : categoryId).tag(categoryId)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("Title", text: $title)
                        .textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Summary")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $summary)
                            .frame(height: 72)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(LisdoMacTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                    }

                    Picker("Priority", selection: $priority) {
                        Text("None").tag(Optional<TodoPriority>.none)
                        Text("Low").tag(Optional(TodoPriority.low))
                        Text("Medium").tag(Optional(TodoPriority.medium))
                        Text("High").tag(Optional(TodoPriority.high))
                    }
                    .pickerStyle(.segmented)

                    Picker("Date", selection: $dateMode) {
                        ForEach(LisdoMacTodoDateMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if dateMode != .none {
                        DatePicker(
                            dateMode == .due ? "Due date" : "Scheduled time",
                            selection: $selectedDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                    }

                    TextField("Original date phrase, optional", text: $dueDateText)
                        .textFieldStyle(.roundedBorder)
                    Text("Use the picker for the saved date. The original phrase is only shown as context from the draft.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Todo")
                }

                Section {
                    if blocks.isEmpty {
                        Text("No checklist items.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(blocks.indices, id: \.self) { index in
                            blockEditorRow(index)
                        }
                    }

                    Button {
                        blocks.append(TodoBlockEditorDraft(type: .checkbox, content: "", checked: false, order: blocks.count))
                    } label: {
                        Label("Add item", systemImage: "plus")
                    }
                } header: {
                    Text("Checklist")
                }

                Section {
                    if reminders.isEmpty {
                        Text("No reminders.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(reminders.indices, id: \.self) { index in
                            reminderEditorRow(index)
                        }
                    }

                    Button {
                    reminders.append(TodoReminderEditorDraft(title: "", reminderDateText: "", reminderDate: defaultReminderDate, hasReminderDate: false, reason: "", isCompleted: false, order: reminders.count))
                } label: {
                    Label("Add reminder", systemImage: "bell.badge")
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("Reminder text is saved on the todo. Turn on Notify and set a concrete time to schedule a local macOS notification.")
                    .foregroundStyle(.secondary)
            }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .padding(20)
            .navigationTitle("Edit Todo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func blockEditorRow(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Toggle("Done", isOn: Binding(
                    get: { blocks[index].checked },
                    set: { blocks[index].checked = $0 }
                ))
                .toggleStyle(.checkbox)

                Picker("Type", selection: Binding(
                    get: { blocks[index].type },
                    set: { blocks[index].type = $0 }
                )) {
                    Text("Checkbox").tag(TodoBlockType.checkbox)
                    Text("Bullet").tag(TodoBlockType.bullet)
                    Text("Note").tag(TodoBlockType.note)
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Spacer()

                Button(role: .destructive) {
                    blocks.remove(at: index)
                    reorderDrafts()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove item")
            }

            TextField("Item text", text: Binding(
                get: { blocks[index].content },
                set: { blocks[index].content = $0 }
            ))
            .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 4)
    }

    private func reminderEditorRow(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Toggle("Done", isOn: Binding(
                    get: { reminders[index].isCompleted },
                    set: { reminders[index].isCompleted = $0 }
                ))
                .toggleStyle(.checkbox)

                Spacer()

                Button(role: .destructive) {
                    reminders.remove(at: index)
                    reorderDrafts()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove reminder")
            }

            TextField("Reminder title", text: Binding(
                get: { reminders[index].title },
                set: { reminders[index].title = $0 }
            ))
            .textFieldStyle(.roundedBorder)

            TextField("Reminder time", text: Binding(
                get: { reminders[index].reminderDateText },
                set: { reminders[index].reminderDateText = $0 }
            ))
            .textFieldStyle(.roundedBorder)

            Toggle("Notify", isOn: Binding(
                get: { reminders[index].hasReminderDate },
                set: { reminders[index].hasReminderDate = $0 }
            ))
            .toggleStyle(.checkbox)

            if reminders[index].hasReminderDate {
                DatePicker("Notification time", selection: Binding(
                    get: { reminders[index].reminderDate },
                    set: { reminders[index].reminderDate = $0 }
                ))
                .datePickerStyle(.compact)
            }

            TextField("Reason", text: Binding(
                get: { reminders[index].reason },
                set: { reminders[index].reason = $0 }
            ))
            .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 4)
    }

    private func save() {
        let trimmedTitle = title.lisdoTrimmed
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Todo title cannot be empty."
            return
        }

        todo.categoryId = categoryId
        todo.title = trimmedTitle
        todo.summary = optionalTrimmed(summary)
        todo.dueDateText = optionalTrimmed(dueDateText)
        switch dateMode {
        case .none:
            todo.dueDate = nil
            todo.scheduledDate = nil
        case .due:
            todo.dueDate = selectedDate
            todo.scheduledDate = nil
        case .scheduled:
            todo.dueDate = nil
            todo.scheduledDate = selectedDate
        }
        todo.priority = priority
        todo.updatedAt = Date()

        syncBlocks()
        syncReminders()

        do {
            try modelContext.save()
            Task { @MainActor in
                await LisdoReminderNotificationScheduler.syncNotifications(for: todo)
            }
            dismiss()
        } catch {
            errorMessage = "Could not save todo: \(error.localizedDescription)"
        }
    }

    private func syncBlocks() {
        let existingBlocks = todo.blocks ?? []
        let sanitizedDrafts = blocks
            .enumerated()
            .compactMap { index, draft -> TodoBlockEditorDraft? in
                let content = draft.content.lisdoTrimmed
                guard !content.isEmpty else { return nil }
                var updated = draft
                updated.content = content
                updated.order = index
                return updated
            }

        let keptIds = Set(sanitizedDrafts.map(\.id))
        existingBlocks
            .filter { !keptIds.contains($0.id) }
            .forEach(modelContext.delete)

        todo.blocks = sanitizedDrafts.map { draft in
            let block: TodoBlock
            if let existingBlock = existingBlocks.first(where: { $0.id == draft.id }) {
                block = existingBlock
            } else {
                block = TodoBlock(
                    id: draft.id,
                    todoId: todo.id,
                    todo: todo,
                    type: draft.type,
                    content: draft.content,
                    checked: draft.checked,
                    order: draft.order
                )
                modelContext.insert(block)
            }
            block.todo = todo
            block.todoId = todo.id
            block.type = draft.type
            block.content = draft.content
            block.checked = draft.checked
            block.order = draft.order
            return block
        }
    }

    private func syncReminders() {
        let existingReminders = todo.reminders ?? []
        let sanitizedDrafts = reminders
            .enumerated()
            .compactMap { index, draft -> TodoReminderEditorDraft? in
                let title = draft.title.lisdoTrimmed
                guard !title.isEmpty else { return nil }
                var updated = draft
                updated.title = title
                updated.reminderDateText = draft.reminderDateText.lisdoTrimmed
                updated.reason = draft.reason.lisdoTrimmed
                updated.order = index
                return updated
            }

        let keptIds = Set(sanitizedDrafts.map(\.id))
        let removedReminderIDs = existingReminders
            .filter { !keptIds.contains($0.id) }
            .map(\.id)
        if !removedReminderIDs.isEmpty {
            Task { await LisdoReminderNotificationScheduler.cancel(reminderIDs: removedReminderIDs) }
        }
        existingReminders
            .filter { !keptIds.contains($0.id) }
            .forEach(modelContext.delete)

        todo.reminders = sanitizedDrafts.map { draft in
            let reminder: TodoReminder
            if let existingReminder = existingReminders.first(where: { $0.id == draft.id }) {
                reminder = existingReminder
            } else {
                reminder = TodoReminder(
                    id: draft.id,
                    todoId: todo.id,
                    todo: todo,
                    title: draft.title,
                    reminderDateText: optionalTrimmed(draft.reminderDateText),
                    reminderDate: draft.hasReminderDate ? draft.reminderDate : nil,
                    reason: optionalTrimmed(draft.reason),
                    isCompleted: draft.isCompleted,
                    updatedAt: Date(),
                    order: draft.order
                )
                modelContext.insert(reminder)
            }
            reminder.todo = todo
            reminder.todoId = todo.id
            reminder.title = draft.title
            reminder.reminderDateText = optionalTrimmed(draft.reminderDateText)
            reminder.reminderDate = draft.hasReminderDate ? draft.reminderDate : nil
            reminder.reason = optionalTrimmed(draft.reason)
            reminder.isCompleted = draft.isCompleted
            reminder.updatedAt = Date()
            reminder.order = draft.order
            return reminder
        }
    }

    private func reorderDrafts() {
        blocks = blocks.enumerated().map { index, draft in
            var updated = draft
            updated.order = index
            return updated
        }
        reminders = reminders.enumerated().map { index, draft in
            var updated = draft
            updated.order = index
            return updated
        }
    }

    private func optionalTrimmed(_ value: String) -> String? {
        let trimmed = value.lisdoTrimmed
        return trimmed.isEmpty ? nil : trimmed
    }

    private var defaultReminderDate: Date {
        Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    }
}

private struct TodoBlockEditorDraft: Identifiable, Equatable {
    var id: UUID
    var type: TodoBlockType
    var content: String
    var checked: Bool
    var order: Int

    init(block: TodoBlock) {
        self.id = block.id
        self.type = block.type
        self.content = block.content
        self.checked = block.checked
        self.order = block.order
    }

    init(type: TodoBlockType, content: String, checked: Bool, order: Int) {
        self.id = UUID()
        self.type = type
        self.content = content
        self.checked = checked
        self.order = order
    }
}

private struct TodoReminderEditorDraft: Identifiable, Equatable {
    var id: UUID
    var title: String
    var reminderDateText: String
    var reminderDate: Date
    var hasReminderDate: Bool
    var reason: String
    var isCompleted: Bool
    var order: Int

    init(reminder: TodoReminder) {
        self.id = reminder.id
        self.title = reminder.title
        self.reminderDateText = reminder.reminderDateText ?? ""
        self.reminderDate = reminder.reminderDate ?? (Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date())
        self.hasReminderDate = reminder.reminderDate != nil
        self.reason = reminder.reason ?? ""
        self.isCompleted = reminder.isCompleted
        self.order = reminder.order
    }

    init(title: String, reminderDateText: String, reminderDate: Date, hasReminderDate: Bool, reason: String, isCompleted: Bool, order: Int) {
        self.id = UUID()
        self.title = title
        self.reminderDateText = reminderDateText
        self.reminderDate = reminderDate
        self.hasReminderDate = hasReminderDate
        self.reason = reason
        self.isCompleted = isCompleted
        self.order = order
    }
}

struct LisdoPlanView: View {
    @Environment(\.modelContext) private var modelContext

    let todos: [Todo]
    let categories: [Category]
    let onOpenTodo: (Todo) -> Void
    @State private var selectedMode: LisdoPlanCalendarMode = .week
    @State private var selectedDate = Date()
    @State private var planStatus: String?
    @State private var editingTodo: Todo?
    private let calendar = Calendar.current
    private var now: Date { Date() }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    planHeader

                    if usesMonthSideBySide(in: geometry.size) {
                        HStack(alignment: .top, spacing: 18) {
                            planCalendar
                                .frame(width: monthCalendarWidth(in: geometry.size), alignment: .topLeading)

                            VStack(alignment: .leading, spacing: 18) {
                                planDetailContent
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        planCalendar
                        planDetailContent
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(LisdoMacTheme.surface)
        }
        .background(LisdoMacTheme.surface)
        .sheet(isPresented: Binding(get: { editingTodo != nil }, set: { if !$0 { editingTodo = nil } })) {
            if let todo = editingTodo {
                LisdoMacTodoEditorSheet(todo: todo, categories: categories)
                    .frame(width: 620, height: 560)
            }
        }
    }

    private var planHeader: some View {
        LisdoSectionHeader(
            "Plan",
            subtitle: "Calendar-style planning from Lisdo due and scheduled dates."
        )
    }

    private var planCalendar: some View {
        LisdoPlanCalendarBand(
            selectedMode: $selectedMode,
            selectedDate: $selectedDate,
            todos: planTodos,
            calendar: calendar
        )
    }

    @ViewBuilder
    private var planDetailContent: some View {
        if let planStatus {
            Text(planStatus)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
        }

        if visibleDatedTodos.isEmpty && (selectedMode == .day || noDateTodos.isEmpty) {
            LisdoEmptyState(
                systemImage: "calendar",
                title: emptyTitle,
                message: emptyMessage
            )
        } else {
            if !visibleDatedTodos.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    LisdoPlanListSectionHeader(
                        title: selectedMode.listTitle,
                        detail: selectedRangeLabel,
                        count: visibleDatedTodos.count
                    )

                    ForEach(visibleDatedTodos, id: \.id) { todo in
                        LisdoPlanTodoRow(
                            todo: todo,
                            category: categories.category(id: todo.categoryId),
                            reminders: reminders(for: todo.id),
                            calendar: calendar,
                            now: now,
                            onToggleCompletion: { toggleCompletion(todo) },
                            onOpen: { onOpenTodo(todo) },
                            onEdit: { editingTodo = todo },
                            onDelete: { deleteTodo(todo) }
                        )
                    }
                }
                .padding(.top, 4)
            }

            if selectedMode != .day && !noDateTodos.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    LisdoPlanListSectionHeader(
                        title: "No Date",
                        detail: "Approved todos without a resolved Lisdo due or scheduled date.",
                        count: noDateTodos.count
                    )

                    ForEach(noDateTodos, id: \.id) { todo in
                        LisdoPlanTodoRow(
                            todo: todo,
                            category: categories.category(id: todo.categoryId),
                            reminders: reminders(for: todo.id),
                            calendar: calendar,
                            now: now,
                            onToggleCompletion: { toggleCompletion(todo) },
                            onOpen: { onOpenTodo(todo) },
                            onEdit: { editingTodo = todo },
                            onDelete: { deleteTodo(todo) }
                        )
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func usesMonthSideBySide(in size: CGSize) -> Bool {
        guard selectedMode == .month else { return false }
        let calendarWidth = max(size.width - 48, 1)
        let calendarAspectRatio = calendarWidth / monthCalendarEstimatedHeight
        return calendarAspectRatio > 1.2 && size.width >= 900
    }

    private func monthCalendarWidth(in size: CGSize) -> CGFloat {
        min(520, max(430, size.width * 0.38))
    }

    private var monthCalendarEstimatedHeight: CGFloat {
        let weekRows = CGFloat(max(monthWeeks.count, 5))
        return 14 + 42 + 36 + 18 + 18 + (weekRows * 56) + (max(weekRows - 1, 0) * 8)
    }

    private var plan: AdvancedPlanSnapshot {
        AdvancedPlanBuilder.makeSnapshot(todos: planTodos, categories: categories, calendar: calendar, now: now)
    }

    private var planTodos: [Todo] {
        todos.filter { $0.status != .archived }
    }

    private var selectedInterval: DateInterval {
        switch selectedMode {
        case .day:
            let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start
                ?? calendar.startOfDay(for: selectedDate)
            return calendar.dateInterval(of: .weekOfYear, for: selectedDate)
                ?? DateInterval(start: start, duration: 60 * 60 * 24 * 7)
        case .week:
            let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start
                ?? calendar.startOfDay(for: selectedDate)
            return calendar.dateInterval(of: .weekOfYear, for: selectedDate)
                ?? DateInterval(start: start, duration: 60 * 60 * 24 * 7)
        case .month:
            let start = calendar.dateInterval(of: .month, for: selectedDate)?.start
                ?? calendar.startOfDay(for: selectedDate)
            return calendar.dateInterval(of: .month, for: selectedDate)
                ?? DateInterval(start: start, duration: 60 * 60 * 24 * 31)
        }
    }

    private var visibleDatedTodos: [Todo] {
        sortedTodos(planTodos.filter { todo in
            guard let planDate = planDate(for: todo) else { return false }
            return selectedInterval.contains(planDate)
        })
    }

    private var noDateTodos: [Todo] {
        sortedTodos(planTodos.filter { planDate(for: $0) == nil })
    }

    private var monthWeeks: [[Date]] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate) else {
            return [weekDates]
        }

        let lastMonthDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) ?? monthInterval.start
        let gridStart = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start)?.start ?? monthInterval.start
        let gridEnd = calendar.dateInterval(of: .weekOfYear, for: lastMonthDay)?.end ?? monthInterval.end

        var weeks: [[Date]] = []
        var weekStart = gridStart
        while weekStart < gridEnd {
            weeks.append((0..<7).compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: weekStart)
            })

            guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) else {
                break
            }
            weekStart = nextWeek
        }

        return weeks
    }

    private var selectedRangeLabel: String {
        switch selectedMode {
        case .day:
            return selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        case .week:
            guard let first = weekDates.first, let last = weekDates.last else {
                return "Selected week"
            }
            return "\(first.formatted(.dateTime.month(.abbreviated).day()))-\(last.formatted(.dateTime.month(.abbreviated).day().year()))"
        case .month:
            return selectedDate.formatted(.dateTime.month(.wide).year())
        }
    }

    private var weekDates: [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start)
        }
    }

    private var emptyTitle: String {
        switch selectedMode {
        case .day:
            return "No dated todos for this week"
        case .week:
            return "No todos for this week"
        case .month:
            return "No todos for this month"
        }
    }

    private var emptyMessage: String {
        switch selectedMode {
        case .day:
            return "Day view shows the selected week and highlights the chosen day."
        case .week:
            return "Todos with dates in this week appear here. No-date todos appear in their own section when present."
        case .month:
            return "Todos with dates in this month appear here. No-date todos remain visible in their own section when present."
        }
    }

    private var completedTodos: [Todo] {
        planTodos.filter { $0.status == .completed }
    }

    private func reminders(for todoId: UUID) -> [TodoReminder] {
        todos.first(where: { $0.id == todoId })?.reminders?.sortedForMacReminderDisplay() ?? []
    }

    private func planDate(for todo: Todo) -> Date? {
        todo.resolvedLisdoPlanDate(calendar: calendar, now: now)
    }

    private func sortedTodos(_ todos: [Todo]) -> [Todo] {
        todos.sorted { lhs, rhs in
            let lhsDate = planDate(for: lhs)
            let rhsDate = planDate(for: rhs)

            if lhsDate != rhsDate {
                switch (lhsDate, rhsDate) {
                case let (lhsDate?, rhsDate?):
                    return lhsDate < rhsDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }
            }

            if lhs.status != rhs.status {
                return lhs.status.planSortOrder < rhs.status.planSortOrder
            }

            if lhs.title != rhs.title {
                return lhs.title < rhs.title
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func toggleCompletion(_ todo: Todo) {
        CaptureBatchActions.toggleSavedTodoCompletion(todo)

        do {
            try modelContext.save()
            Task { @MainActor in
                await LisdoReminderNotificationScheduler.syncNotifications(for: todo)
            }
            planStatus = nil
        } catch {
            planStatus = "Could not update todo: \(error.localizedDescription)"
        }
    }

    private func deleteTodo(_ todo: Todo) {
        let reminderIDs = (todo.reminders ?? []).map(\.id)
        TodoTrashPolicy.moveToTrash([todo])

        do {
            try modelContext.save()
            Task { await LisdoReminderNotificationScheduler.cancel(reminderIDs: reminderIDs) }
            planStatus = "Moved todo to Trash."
        } catch {
            planStatus = "Could not move todo to Trash: \(error.localizedDescription)"
        }
    }

    private func archiveCompleted() {
        let archived = CaptureBatchActions.archiveCompletedTodos(completedTodos)
        do {
            try modelContext.save()
            planStatus = "Archived \(archived.count) completed todo\(archived.count == 1 ? "" : "s")."
        } catch {
            planStatus = "Could not archive completed todos: \(error.localizedDescription)"
        }
    }
}

private enum LisdoPlanCalendarMode: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }

    var listTitle: String {
        switch self {
        case .day:
            return "Day"
        case .week:
            return "Week"
        case .month:
            return "Month"
        }
    }
}

private struct LisdoPlanModePill: View {
    @Binding var selectedMode: LisdoPlanCalendarMode
    @Namespace private var selectionNamespace

    private let segmentWidth: CGFloat = 66
    private let segmentHeight: CGFloat = 30

    var body: some View {
        HStack(spacing: 0) {
            ForEach(LisdoPlanCalendarMode.allCases) { mode in
                Button {
                    setMode(mode)
                } label: {
                    Text(mode.rawValue)
                        .font(.callout.weight(selectedMode == mode ? .semibold : .medium))
                        .foregroundStyle(selectedMode == mode ? LisdoMacTheme.ink1 : LisdoMacTheme.ink3)
                        .frame(width: segmentWidth, height: segmentHeight)
                        .contentShape(Capsule())
                        .background {
                            if selectedMode == mode {
                                Color.clear
                                    .matchedGeometryEffect(id: "selectedPlanMode", in: selectionNamespace)
                                    .lisdoGlassSurface(
                                        cornerRadius: segmentHeight / 2,
                                        tint: LisdoMacTheme.info.opacity(0.14),
                                        interactive: true
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.rawValue) view")
            }
        }
        .padding(3)
        .lisdoGlassSurface(cornerRadius: 18, interactive: true)
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    guard abs(value.translation.width) > 18 else { return }
                    let step = value.translation.width < 0 ? 1 : -1
                    moveSelection(by: step)
                }
        )
        .accessibilityLabel("Calendar view")
    }

    private func setMode(_ mode: LisdoPlanCalendarMode) {
        withAnimation(.snappy(duration: 0.22)) {
            selectedMode = mode
        }
    }

    private func moveSelection(by offset: Int) {
        let modes = LisdoPlanCalendarMode.allCases
        guard let currentIndex = modes.firstIndex(of: selectedMode) else { return }
        let nextIndex = min(max(currentIndex + offset, modes.startIndex), modes.index(before: modes.endIndex))
        setMode(modes[nextIndex])
    }
}

private struct LisdoPlanCalendarBand: View {
    @Binding var selectedMode: LisdoPlanCalendarMode
    @Binding var selectedDate: Date
    let todos: [Todo]
    let calendar: Calendar
    private let monthDateMarkSize: CGFloat = 52
    private let monthDateSpacing: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(rangeLabel)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text("Lisdo-only due and scheduled dates")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .layoutPriority(1)

                Spacer()

                LisdoPlanModePill(selectedMode: $selectedMode)
            }

            HStack(spacing: 8) {
                Button {
                    shiftSelection(by: -1)
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                }
                .labelStyle(.iconOnly)
                .lisdoGlassButtonStyle()
                .buttonBorderShape(.capsule)
                .controlSize(.small)

                Button("Today") {
                    selectedDate = Date()
                }
                .lisdoGlassButtonStyle(prominent: calendar.isDateInToday(selectedDate))
                .buttonBorderShape(.capsule)
                .controlSize(.small)

                Button {
                    shiftSelection(by: 1)
                } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .labelStyle(.iconOnly)
                .lisdoGlassButtonStyle()
                .buttonBorderShape(.capsule)
                .controlSize(.small)

                Spacer()

                Text(countLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

#if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 8) {
                    calendarBodyContent
                }
            } else {
                calendarBodyContent
            }
#else
            calendarBodyContent
#endif
        }
        .padding(14)
        .lisdoGlassSurface(cornerRadius: 18)
    }

    @ViewBuilder
    private var calendarBodyContent: some View {
        switch selectedMode {
        case .day:
            HStack(spacing: 8) {
                ForEach(weekDates(for: selectedDate), id: \.self) { date in
                    Button {
                        selectedDate = date
                    } label: {
                        LisdoPlanCalendarDayCell(
                            date: date,
                            count: todoCount(on: date),
                            isToday: calendar.isDateInToday(date),
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                }
            }
        case .week:
            HStack(spacing: 8) {
                ForEach(weekDates(for: selectedDate), id: \.self) { date in
                    Button {
                        selectedDate = date
                        selectedMode = .day
                    } label: {
                        LisdoPlanCalendarDayCell(
                            date: date,
                            count: todoCount(on: date),
                            isToday: calendar.isDateInToday(date),
                            isSelected: false
                        )
                    }
                    .buttonStyle(.plain)
                    .help(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                }
            }
        case .month:
            VStack(spacing: 8) {
                HStack(spacing: monthDateSpacing) {
                    ForEach(weekDates(for: selectedDate), id: \.self) { date in
                        Text(date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .frame(width: monthDateMarkSize)
                    }
                }
                .frame(maxWidth: .infinity)

                ForEach(monthWeeks, id: \.self) { week in
                    Button {
                        selectedDate = week.first ?? selectedDate
                        selectedMode = .week
                    } label: {
                        LisdoPlanCalendarMonthWeekRow(
                            week: week,
                            selectedDate: selectedDate,
                            calendar: calendar,
                            markSize: monthDateMarkSize,
                            dateSpacing: monthDateSpacing,
                            todoCount: todoCount(on:)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(weekRangeLabel(for: week))
                }
            }
        }
    }

    private var rangeLabel: String {
        switch selectedMode {
        case .day:
            return selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        case .week:
            return weekRangeLabel(for: weekDates(for: selectedDate))
        case .month:
            return selectedDate.formatted(.dateTime.month(.wide).year())
        }
    }

    private var countLabel: String {
        let count = todos.filter { todo in
            guard let date = todo.scheduledDate ?? todo.dueDate else { return false }
            return selectedInterval.contains(date)
        }.count

        return count == 1 ? "1 dated todo" : "\(count) dated todos"
    }

    private var selectedInterval: DateInterval {
        switch selectedMode {
        case .day:
            let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start
                ?? calendar.startOfDay(for: selectedDate)
            return calendar.dateInterval(of: .weekOfYear, for: selectedDate)
                ?? DateInterval(start: start, duration: 60 * 60 * 24 * 7)
        case .week:
            let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start
                ?? calendar.startOfDay(for: selectedDate)
            return calendar.dateInterval(of: .weekOfYear, for: selectedDate)
                ?? DateInterval(start: start, duration: 60 * 60 * 24 * 7)
        case .month:
            let start = calendar.dateInterval(of: .month, for: selectedDate)?.start
                ?? calendar.startOfDay(for: selectedDate)
            return calendar.dateInterval(of: .month, for: selectedDate)
                ?? DateInterval(start: start, duration: 60 * 60 * 24 * 31)
        }
    }

    private var monthWeeks: [[Date]] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate) else {
            return [weekDates(for: selectedDate)]
        }

        let lastMonthDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) ?? monthInterval.start
        let gridStart = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start)?.start ?? monthInterval.start
        let gridEnd = calendar.dateInterval(of: .weekOfYear, for: lastMonthDay)?.end ?? monthInterval.end

        var weeks: [[Date]] = []
        var weekStart = gridStart
        while weekStart < gridEnd {
            let week = (0..<7).compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: weekStart)
            }
            weeks.append(week)

            guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) else {
                break
            }
            weekStart = nextWeek
        }

        return weeks
    }

    private func shiftSelection(by value: Int) {
        let component: Calendar.Component
        switch selectedMode {
        case .day:
            component = .day
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        }

        selectedDate = calendar.date(byAdding: component, value: value, to: selectedDate) ?? selectedDate
    }

    private func weekDates(for date: Date) -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start)
        }
    }

    private func todoCount(on date: Date) -> Int {
        todos.filter { todo in
            guard let itemDate = todo.scheduledDate ?? todo.dueDate else { return false }
            return calendar.isDate(itemDate, inSameDayAs: date)
        }.count
    }

    private func weekRangeLabel(for week: [Date]) -> String {
        guard let first = week.first, let last = week.last else {
            return "Selected week"
        }

        return "\(first.formatted(.dateTime.month(.abbreviated).day()))-\(last.formatted(.dateTime.month(.abbreviated).day().year()))"
    }
}

private struct LisdoPlanCalendarDayCell: View {
    let date: Date
    let count: Int
    let isToday: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 7) {
            Text(date.formatted(.dateTime.weekday(.narrow)))
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(dayNumberForeground)
                .frame(width: 34, height: 28)

            HStack(spacing: 3) {
                if count == 0 {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 5, height: 5)
                } else {
                    ForEach(0..<min(count, 3), id: \.self) { _ in
                        Circle()
                            .fill(isSelected ? LisdoMacTheme.info.opacity(0.86) : LisdoMacTheme.ink4.opacity(0.72))
                            .frame(width: 5, height: 5)
                    }

                    if count > 3 {
                        Text("+\(count - 3)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 10)

            Text(count == 1 ? "1 item" : "\(count) items")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .opacity(count == 0 ? 0.58 : 1)
        }
        .frame(maxWidth: .infinity, minHeight: 82)
        .padding(.vertical, 8)
        .lisdoGlassSurface(cornerRadius: 14, tint: glassTint, interactive: true)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(borderColor, lineWidth: borderLineWidth)
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var dayNumberForeground: Color {
        isSelected && !isToday ? LisdoMacTheme.info : LisdoMacTheme.ink1
    }

    private var glassTint: Color? {
        if isSelected {
            return LisdoMacTheme.info.opacity(0.10)
        }
        return count > 0 ? LisdoMacTheme.ink4.opacity(0.08) : nil
    }

    private var borderColor: Color {
        if isToday {
            return LisdoMacTheme.onAccent.opacity(0.9)
        }
        if isSelected {
            return LisdoMacTheme.info.opacity(0.5)
        }
        return LisdoMacTheme.divider.opacity(0.72)
    }

    private var borderLineWidth: CGFloat {
        isToday || isSelected ? 1.2 : 1
    }

    private var accessibilityLabel: String {
        let day = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        return count == 1 ? "\(day), 1 Lisdo item" : "\(day), \(count) Lisdo items"
    }
}

private struct LisdoPlanCalendarMonthWeekRow: View {
    let week: [Date]
    let selectedDate: Date
    let calendar: Calendar
    let markSize: CGFloat
    let dateSpacing: CGFloat
    let todoCount: (Date) -> Int

    var body: some View {
        HStack(spacing: dateSpacing) {
            ForEach(week, id: \.self) { date in
                LisdoPlanCalendarMonthDateMark(
                    date: date,
                    count: todoCount(date),
                    isToday: calendar.isDateInToday(date),
                    isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                    isCurrentMonth: calendar.isDate(date, equalTo: selectedDate, toGranularity: .month),
                    todayFrameSize: markSize
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: markSize)
        .lisdoGlassSurface(cornerRadius: 14, interactive: true)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(LisdoMacTheme.divider.opacity(0.72))
        }
        .accessibilityLabel(weekLabel)
    }

    private var weekLabel: String {
        guard let first = week.first, let last = week.last else {
            return "Week"
        }
        return "\(first.formatted(.dateTime.month(.abbreviated).day())) to \(last.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

private struct LisdoPlanCalendarMonthDateMark: View {
    let date: Date
    let count: Int
    let isToday: Bool
    let isSelected: Bool
    let isCurrentMonth: Bool
    let todayFrameSize: CGFloat

    var body: some View {
        ZStack {
            if isToday {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(LisdoMacTheme.onAccent.opacity(0.9), lineWidth: 1.2)
            }

            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 18, weight: isToday || isSelected ? .bold : .semibold))
                    .foregroundStyle(dayForeground)
                    .frame(width: 32, height: 28)
                    .background(dayBackground, in: Circle())

                Circle()
                    .fill(count > 0 ? dotColor : Color.clear)
                    .frame(width: 4, height: 4)
            }
        }
        .frame(width: todayFrameSize, height: todayFrameSize)
        .opacity(isCurrentMonth ? 1 : 0.42)
    }

    private var dayForeground: Color {
        if isSelected {
            return LisdoMacTheme.info
        }
        return .primary
    }

    private var dayBackground: Color {
        if isSelected && !isToday {
            return LisdoMacTheme.info.opacity(0.14)
        }
        return .clear
    }

    private var dotColor: Color {
        isToday || isSelected ? LisdoMacTheme.info : LisdoMacTheme.ink4.opacity(0.72)
    }
}

private struct LisdoPlanListSectionHeader: View {
    let title: String
    let detail: String
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text(count == 1 ? "1 todo" : "\(count) todos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                LisdoChip(title: title, systemImage: title == "No Date" ? "tray" : "calendar")
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct LisdoPlanTodoRow: View {
    let todo: Todo
    let category: Category?
    let reminders: [TodoReminder]
    let calendar: Calendar
    let now: Date
    var onToggleCompletion: (() -> Void)?
    var onOpen: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                onToggleCompletion?()
            } label: {
                Image(systemName: completionImage)
                    .font(.title3)
                    .foregroundStyle(todo.status == .completed ? .secondary : .primary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(onToggleCompletion == nil)
            .accessibilityLabel(todo.status == .completed ? "Reopen todo" : "Complete todo")

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    LisdoCategoryDot(category: category)
                    Text(category?.name ?? "Inbox")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Label(timingLabel, systemImage: timingIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let priority = todo.priority {
                        Text("· \(priorityLabel(priority))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if todo.status == .completed {
                        Text("· Completed")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else if todo.status == .inProgress {
                        Text("· In progress")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(todo.title)
                    .font(.headline)
                    .foregroundStyle(todo.status == .completed ? .secondary : .primary)
                    .strikethrough(todo.status == .completed, color: .secondary)

                if let summary = todo.summary {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !reminders.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "bell")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(planReminderLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.top, 1)
                }
            }

            Spacer(minLength: 0)

            if onEdit != nil || onDelete != nil {
                HStack(alignment: .center, spacing: 4) {
                    if let onEdit {
                        LisdoMacIconActionButton(
                            systemName: "pencil",
                            accessibilityLabel: "Edit todo",
                            action: onEdit
                        )
                    }

                    if let onDelete {
                        LisdoMacIconActionButton(
                            systemName: "trash",
                            accessibilityLabel: "Delete todo",
                            role: .destructive,
                            action: onDelete
                        )
                    }
                }
                .frame(height: 28, alignment: .center)
            }
        }
        .padding(14)
        .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(LisdoMacTheme.divider.opacity(0.72))
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            onOpen?()
        }
        .contextMenu {
            if let onToggleCompletion {
                Button {
                    onToggleCompletion()
                } label: {
                    Label(todo.status == .completed ? "Reopen Todo" : "Complete Todo", systemImage: todo.status == .completed ? "circle" : "checkmark.circle")
                }
            }

            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Edit Todo", systemImage: "pencil")
                }
            }

            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Todo", systemImage: "trash")
                }
            }
        }
    }

    private var completionImage: String {
        if todo.status == .completed {
            return "checkmark.circle.fill"
        }
        if todo.status == .inProgress {
            return "circle.dotted"
        }
        return "circle"
    }

    private var timingIcon: String {
        guard let itemDate = todo.resolvedLisdoPlanDate(calendar: calendar, now: now) else {
            return "tray"
        }

        if calendar.startOfDay(for: itemDate) < calendar.startOfDay(for: now), todo.status != .completed {
            return "exclamationmark.circle"
        }

        return "calendar"
    }

    private var timingLabel: String {
        if let scheduledDate = todo.scheduledDate {
            return "Scheduled \(dateLabel(for: scheduledDate))"
        }
        if let dueDate = todo.dueDate {
            return "Due \(dateLabel(for: dueDate))"
        }
        if let dueDateText = todo.dueDateText?.lisdoTrimmed, !dueDateText.isEmpty {
            return "Due \(dueDateText)"
        }
        return "No date"
    }

    private func dateLabel(for date: Date) -> String {
        let includesTime = calendar.component(.hour, from: date) != 0
            || calendar.component(.minute, from: date) != 0

        if calendar.isDateInToday(date) {
            return includesTime
                ? "today, \(date.formatted(.dateTime.hour().minute()))"
                : "today"
        }

        if calendar.isDateInTomorrow(date) {
            return includesTime
                ? "tomorrow, \(date.formatted(.dateTime.hour().minute()))"
                : "tomorrow"
        }

        return includesTime
            ? date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
            : date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func priorityLabel(_ priority: TodoPriority) -> String {
        switch priority {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }

    private var planReminderLabel: String {
        let count = reminders.count
        guard let first = reminders.first else {
            return "No reminders"
        }

        let prefix = count == 1 ? "1 reminder" : "\(count) reminders"
        if let dateText = first.reminderDateText?.lisdoTrimmed, !dateText.isEmpty {
            return "\(prefix): \(first.title) · \(dateText)"
        }
        if let reminderDate = first.reminderDate {
            return "\(prefix): \(first.title) · \(reminderDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
        }
        return "\(prefix): \(first.title)"
    }
}

private extension TodoStatus {
    var planSortOrder: Int {
        switch self {
        case .inProgress:
            return 0
        case .open:
            return 1
        case .completed:
            return 2
        case .archived:
            return 3
        case .trashed:
            return 4
        }
    }
}

private extension Array where Element == TodoReminder {
    func sortedForMacReminderDisplay() -> [TodoReminder] {
        sorted { lhs, rhs in
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }

            if lhs.title != rhs.title {
                return lhs.title < rhs.title
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

private extension Array where Element == TodoBlock {
    func sortedForMacTodoDisplay() -> [TodoBlock] {
        sorted { lhs, rhs in
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }

            if lhs.content != rhs.content {
                return lhs.content < rhs.content
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

private extension CategorySchemaPreset {
    var displayName: String {
        switch self {
        case .general:
            return "General"
        case .checklist:
            return "Checklist"
        case .shoppingList:
            return "Shopping List"
        case .research:
            return "Research"
        case .meeting:
            return "Meeting"
        }
    }

    var explanation: String {
        switch self {
        case .general:
            return "Flexible draft shape for mixed captures: concise title, summary, and useful notes or actions."
        case .checklist:
            return "Action-oriented style: creates checkbox steps when the source contains tasks or procedures."
        case .shoppingList:
            return "Shopping style: organizes items as checklist entries, preserving quantities or short notes when available."
        case .research:
            return "Research style: emphasizes context, questions, hypotheses, sources, and next investigation steps."
        case .meeting:
            return "Meeting style: extracts decisions, follow-ups, owners, and dates from notes or transcripts."
        }
    }
}

private extension String {
    var nilIfEmptyForReminderDisplay: String? {
        isEmpty ? nil : self
    }
}

struct LisdoFromIPhoneView: View {
    @Environment(\.modelContext) private var modelContext

    let captures: [CaptureItem]
    let categories: [Category]

    @State private var isProcessingQueue = false
    @State private var queueStatus: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LisdoSectionHeader("From iPhone", subtitle: "Captures waiting for Mac-side processing.") {
                    Button {
                        Task {
                            await processAll()
                        }
                    } label: {
                        Label(isProcessingQueue ? "Processing" : "Process All", systemImage: "sparkles")
                    }
                    .lisdoProcessAllButtonStyle()
                    .disabled(isProcessingQueue || processableCount == 0)
                    .help("Lease pending captures and create reviewable drafts with Mac-only CLI.")
                }

                HStack(spacing: 8) {
                    LisdoChip(title: "\(processableCount) ready", systemImage: "sparkles")
                    LisdoChip(title: "\(failedCount) failed", systemImage: "exclamationmark.triangle")
                    LisdoChip(title: "Mode: \(LisdoMacMVP2Processing.providerModeLabel)", systemImage: "cpu")
                }

                if let queueStatus {
                    Text(queueStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
                }

                if queueCaptures.isEmpty {
                    LisdoEmptyState(
                        systemImage: "icloud",
                        title: "No pending iPhone captures",
                        message: "Shared screenshots, voice transcripts, and text from iPhone will appear here when they need this Mac to organize them."
                    )
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pending queue")
                            .font(.headline)
                        ForEach(queueCaptures, id: \.id) { capture in
                            LisdoPendingCaptureRow(
                                capture: capture,
                                onRetry: capture.status == .failed ? {
                                    retry(capture)
                                } : nil,
                                onProcess: processableCaptures.contains(where: { $0.id == capture.id }) ? {
                                    processLater(capture)
                                } : nil,
                                onDelete: CaptureDeletionPolicy.canDeleteCapture(capture) ? {
                                    deleteCapture(capture)
                                } : nil
                            )
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(LisdoMacTheme.surface)
    }

    private var queueCaptures: [CaptureItem] {
        LisdoMacMVP2Processing.pendingQueue(from: captures)
    }

    private var processableCount: Int {
        processableCaptures.count
    }

    private var processableCaptures: [CaptureItem] {
        CaptureBatchSelector.processablePendingCaptures(from: queueCaptures)
    }

    private var failedCount: Int {
        queueCaptures.filter { $0.status == .failed }.count
    }

    @MainActor
    private func processAll() async {
        guard !isProcessingQueue else { return }

        isProcessingQueue = true
        queueStatus = "Processing \(processableCount) captures on this Mac."
        defer { isProcessingQueue = false }

        let outcome = await LisdoMacMVP2Processing.processAllQueuedCaptures(
            queueCaptures,
            selectedCategoryId: categories.defaultCategoryId,
            categories: categories,
            modelContext: modelContext
        )
        queueStatus = outcome.message
    }

    @MainActor
    private func process(_ capture: CaptureItem) async {
        guard !isProcessingQueue else { return }

        isProcessingQueue = true
        queueStatus = "Processing one capture on this Mac."
        defer { isProcessingQueue = false }

        let outcome = await LisdoMacMVP2Processing.processQueuedCapture(
            capture,
            selectedCategoryId: categories.defaultCategoryId,
            categories: categories,
            modelContext: modelContext
        )
        queueStatus = outcome.message
    }

    private func retry(_ capture: CaptureItem) {
        let outcome = LisdoMacMVP2Processing.retryCapture(capture, modelContext: modelContext)
        queueStatus = outcome.message
    }

    private func deleteCapture(_ capture: CaptureItem) {
        guard CaptureDeletionPolicy.canDeleteCapture(capture) else {
            queueStatus = "Saved todos cannot be deleted from this queue."
            return
        }

        modelContext.delete(capture)

        do {
            try modelContext.save()
            queueStatus = "Deleted iPhone capture."
        } catch {
            queueStatus = "Could not delete capture: \(error.localizedDescription)"
        }
    }

    private func processLater(_ capture: CaptureItem) {
        let task: Task<Void, Never> = Task {
            await process(capture)
        }
        _ = task
    }
}

private extension View {
    func lisdoProcessAllButtonStyle() -> some View {
        buttonStyle(.borderedProminent)
            .tint(LisdoMacTheme.ink2)
    }
}
