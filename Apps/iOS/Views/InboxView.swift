import LisdoCore
import SwiftData
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

struct InboxView: View {
    @Environment(\.modelContext) private var modelContext

    var drafts: [ProcessingDraft]
    var captures: [CaptureItem]
    var todos: [Todo]
    var categories: [Category]
    var openDraft: (ProcessingDraft) -> Void
    var openPomodoro: (Todo) -> Void = { _ in }

    @State private var taskControlMessage: String?
    @State private var taskControlError: String?
    @State private var searchText = ""
    @State private var selectedCaptureStatus: CaptureStatus?
    @State private var selectedCategoryId: String?
    @State private var selectedTodoStatus: TodoStatus?
    @State private var selectedPriority: TodoPriority?
    @State private var showingFilters = false
    @State private var selectedTodoDetail: TodoDetailSelection?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header

                if showsBatchActions {
                    batchActions
                }

                if let taskControlMessage {
                    ProductStateRow(
                        icon: "livephoto",
                        title: "Active task",
                        message: taskControlMessage
                    )
                }

                if let taskControlError {
                    ProductStateRow(
                        icon: "exclamationmark.triangle",
                        title: "Task update failed",
                        message: taskControlError
                    )
                }

                if !filteredDrafts.isEmpty {
                    Section {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredDrafts, id: \.id) { draft in
                                DraftCardView(
                                    draft: draft,
                                    categoryName: categoryName(for: draft.recommendedCategoryId),
                                    open: { openDraft(draft) }
                                )
                                .contextMenu {
                                    Button {
                                        saveDraftAsTodo(draft)
                                    } label: {
                                        Label("Save", systemImage: "checkmark")
                                    }

                                    Button(role: .destructive) {
                                        deleteDraft(draft)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    } header: {
                        LisdoSectionHeader(title: "Drafts", detail: "\(filteredDrafts.count)")
                    }
                }

                Section {
                    LazyVStack(spacing: 8) {
                        let pending = pendingCaptures
                        if pending.isEmpty {
                            ProductStateRow(
                                icon: "tray",
                                title: "No pending captures",
                                message: "Text, voice, camera, share, and image captures that still need processing will appear here before they become reviewable drafts."
                            )
                        } else {
                            ForEach(pending, id: \.id) { capture in
                                PendingCaptureRow(capture: capture)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            deletePendingCapture(capture)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                } header: {
                    LisdoSectionHeader(title: "Pending", detail: pendingCaptures.isEmpty ? nil : "\(pendingCaptures.count)")
                }

                Section {
                    LazyVStack(spacing: 10) {
                        if todayTodos.isEmpty {
                            ProductStateRow(
                                icon: "calendar",
                                title: "Nothing due today",
                                message: "Saved todos with due text or scheduled dates for today will collect here."
                            )
                        } else {
                            ForEach(todayTodos, id: \.id) { todo in
                                CompactTodoCardView(
                                    todo: todo,
                                    categoryName: categoryName(for: todo.categoryId),
                                    onOpen: { selectedTodoDetail = TodoDetailSelection(todoID: todo.id) },
                                    onStartFocus: { openPomodoro(todo) },
                                    onDelete: { deleteTodo(todo) }
                                )
                            }
                        }
                    }
                } header: {
                    LisdoSectionHeader(title: "Today", detail: todayTodos.isEmpty ? "0 left" : "\(todayTodos.count) left")
                }

                Section {
                    LazyVStack(spacing: 10) {
                        if savedTodos.isEmpty {
                            ProductStateRow(
                                icon: "checkmark.circle",
                                title: "No saved todos yet",
                                message: "A draft becomes a final todo only after you review it and tap Save as todo."
                            )
                        } else {
                            ForEach(savedTodos, id: \.id) { todo in
                                CompactTodoCardView(
                                    todo: todo,
                                    categoryName: categoryName(for: todo.categoryId),
                                    onOpen: { selectedTodoDetail = TodoDetailSelection(todoID: todo.id) },
                                    onStartFocus: { openPomodoro(todo) },
                                    onDelete: { deleteTodo(todo) }
                                )
                            }
                        }
                    }
                } header: {
                    LisdoSectionHeader(title: "Saved", detail: savedTodos.isEmpty ? nil : "\(savedTodos.count)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(LisdoTheme.surface)
        .navigationTitle("Inbox")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search captures, drafts, todos"
        )
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 72)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingFilters = true
                } label: {
                    Label("Filters", systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filters")
            }
        }
        .sheet(isPresented: $showingFilters) {
            InboxFilterSheet(
                selectedCaptureStatus: $selectedCaptureStatus,
                selectedCategoryId: $selectedCategoryId,
                selectedTodoStatus: $selectedTodoStatus,
                selectedPriority: $selectedPriority,
                categories: categories,
                onClear: clearFilters
            )
        }
        .sheet(item: $selectedTodoDetail) { selection in
            if let todo = todos.first(where: { $0.id == selection.todoID }) {
                TodoDetailSheet(
                    todo: todo,
                    categories: categories,
                    openPomodoro: openPomodoro
                )
                .presentationDetents([.fraction(0.78), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(LisdoTheme.surface)
            } else {
                MissingTodoDetailView()
                    .presentationDetents([.medium])
                    .presentationBackground(LisdoTheme.surface)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(greeting)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(LisdoTheme.ink1)
            Label(statusLine, systemImage: "sparkle")
                .font(.system(size: 13))
                .foregroundStyle(LisdoTheme.ink3)
        }
        .padding(.horizontal, 4)
    }

    private var batchActions: some View {
        HStack(spacing: 10) {
            BatchActionButton(
                title: "Process",
                systemImage: "sparkles",
                isProminent: true,
                isDisabled: iPhoneProcessablePendingCaptures.isEmpty
            ) {
                triggerHostedQueueProcessing()
            }

            BatchActionButton(
                title: "Retry",
                systemImage: "arrow.clockwise",
                isProminent: false,
                isDisabled: CaptureBatchSelector.failedCaptures(from: captures).isEmpty
            ) {
                retryFailedCaptures()
            }

            BatchActionButton(
                title: "Archive",
                systemImage: "archivebox",
                isProminent: false,
                isDisabled: todos.filter { $0.status == .completed }.isEmpty
            ) {
                archiveCompletedTodos()
            }
        }
    }

    private var showsBatchActions: Bool {
        !iPhoneProcessablePendingCaptures.isEmpty
            || !CaptureBatchSelector.failedCaptures(from: captures).isEmpty
            || todos.contains { $0.status == .completed }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    private var statusLine: String {
        drafts.isEmpty ? "Inbox is clear" : "\(drafts.count) drafts ready to review"
    }

    private var pendingCaptures: [CaptureItem] {
        filteredCaptures.filter { capture in
            switch capture.status {
            case .rawCaptured, .pendingProcessing, .processing, .failed, .retryPending:
                true
            case .processedDraft, .approvedTodo:
                false
            }
        }
    }

    private var iPhoneProcessablePendingCaptures: [CaptureItem] {
        captures.filter(HostedProviderQueuePolicy.isIPhoneHostedPendingCandidate)
    }

    private var todayTodos: [Todo] {
        visibleFilteredTodos.filter { todo in
            todo.status != .completed && (
                Calendar.current.isDateInToday(todo.dueDate ?? .distantPast)
                || Calendar.current.isDateInToday(todo.scheduledDate ?? .distantPast)
                || (todo.dueDateText?.localizedCaseInsensitiveContains("today") == true)
            )
        }
    }

    private var savedTodos: [Todo] {
        visibleFilteredTodos.filter { todo in
            !todayTodos.contains(where: { $0.id == todo.id })
        }
    }

    private var filteredResult: AdvancedSearchResult {
        LisdoAdvancedSearch.filter(
            captures: captures,
            drafts: drafts,
            todos: todos,
            query: AdvancedSearchQuery(
                text: searchText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                captureStatuses: selectedCaptureStatus.map { [$0] } ?? [],
                providerModes: [],
                categoryIds: selectedCategoryId.map { [$0] } ?? [],
                todoStatuses: selectedTodoStatus.map { [$0] } ?? [],
                priorities: selectedPriority.map { [$0] } ?? []
            )
        )
    }

    private var filteredCaptures: [CaptureItem] { filteredResult.captures }
    private var filteredDrafts: [ProcessingDraft] { filteredResult.drafts }
    private var filteredTodos: [Todo] { filteredResult.todos }
    private var visibleFilteredTodos: [Todo] {
        if let selectedTodoStatus {
            return filteredTodos.filter { $0.status == selectedTodoStatus }
        }

        return filteredTodos.filter { todo in
            todo.status == .open || todo.status == .inProgress
        }
    }

    private var hasActiveFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedCaptureStatus != nil
            || selectedCategoryId != nil
            || selectedTodoStatus != nil
            || selectedPriority != nil
    }

    private func categoryName(for id: String?) -> String {
        categories.first(where: { $0.id == id })?.name ?? "General"
    }

    private func clearFilters() {
        searchText = ""
        selectedCaptureStatus = nil
        selectedCategoryId = nil
        selectedTodoStatus = nil
        selectedPriority = nil
    }

    private func deleteDraft(_ draft: ProcessingDraft) {
        let captureIds = CaptureDeletionPolicy.captureIdsToDelete(whenDeleting: draft, captures: captures)
        for capture in captures where captureIds.contains(capture.id) {
            modelContext.delete(capture)
        }
        modelContext.delete(draft)

        do {
            try modelContext.save()
        } catch {
        }
    }

    private func deletePendingCapture(_ capture: CaptureItem) {
        guard CaptureDeletionPolicy.canDeleteCapture(capture) else {
            return
        }

        do {
            try LisdoPendingAttachmentStore(context: modelContext).deleteAttachments(forCaptureItemId: capture.id)
            modelContext.delete(capture)
            try modelContext.save()
            reloadWidgetTimelines()
        } catch {
        }
    }

    private func saveDraftAsTodo(_ draft: ProcessingDraft) {
        let categoryId = categoryIdForSaving(draft)
        draft.recommendedCategoryId = categoryId
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.summary = draft.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        draft.blocks = draft.blocks
            .map { block in
                var copy = block
                copy.content = copy.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return copy
            }
            .filter { !$0.content.isEmpty }

        do {
            let todo = try DraftApprovalConverter.convert(
                draft,
                categoryId: categoryId,
                approval: DraftApproval(approvedByUser: true)
            )
            modelContext.insert(todo)
            if let capture = captures.first(where: { $0.id == draft.captureItemId }) {
                if capture.status == .processedDraft {
                    try? capture.transition(to: .approvedTodo)
                } else {
                    capture.status = .approvedTodo
                }
            }
            modelContext.delete(draft)
            try modelContext.save()
            Task { @MainActor in
                await LisdoReminderNotificationScheduler.syncNotifications(for: todo)
            }
            reloadWidgetTimelines()
        } catch {
        }
    }

    private func categoryIdForSaving(_ draft: ProcessingDraft) -> String {
        if let recommendedCategoryId = draft.recommendedCategoryId,
           categories.contains(where: { $0.id == recommendedCategoryId }) {
            return recommendedCategoryId
        }

        return categories.first { $0.id == DefaultCategorySeeder.inboxCategoryId }?.id
            ?? categories.first?.id
            ?? DefaultCategorySeeder.inboxCategoryId
    }

    private func retryFailedCaptures() {
        do {
            let retried = try CaptureBatchActions.queueFailedCapturesForRetry(captures)
            try modelContext.save()
            if !retried.isEmpty {
                LisdoHostedPendingQueueProcessor.requestProcessing()
            }
            reloadWidgetTimelines()
        } catch {
        }
    }

    private func archiveCompletedTodos() {
        let archived = CaptureBatchActions.archiveCompletedTodos(todos)
        do {
            try modelContext.save()
            reloadWidgetTimelines()
        } catch {
        }
    }

    private func triggerHostedQueueProcessing() {
        let count = iPhoneProcessablePendingCaptures.count
        guard count > 0 else {
            return
        }

        LisdoHostedPendingQueueProcessor.requestProcessing()
        reloadWidgetTimelines()
    }

    private func captureStatusLabel(_ status: CaptureStatus) -> String {
        status.rawValue.readableEnumLabel
    }

    private func providerLabel(_ mode: ProviderMode) -> String {
        DraftProviderFactory.metadata(for: mode).displayName
    }

    private func categoryFilterLabel(_ id: String) -> String {
        categoryName(for: id)
    }

    private func todoStatusLabel(_ status: TodoStatus) -> String {
        status.rawValue.readableEnumLabel
    }

    private func priorityLabel(_ priority: TodoPriority) -> String {
        priority.rawValue.readableEnumLabel
    }

    private var liveActivityDisabledText: String? {
        LisdoPomodoroActivityController.disabledStatusText
    }

    private func advanceActiveTaskStep(_ todo: Todo) {
        taskControlError = nil
        guard let currentStep = todo.currentWidgetStep else {
            completeTodo(todo)
            return
        }

        currentStep.checked = true
        if todo.status == .open {
            todo.status = .inProgress
        }
        todo.updatedAt = Date()

        guard saveTodoChanges() else { return }
        reloadWidgetTimelines()

        Task { @MainActor in
            taskControlMessage = await LisdoActiveTaskActivityController.startOrUpdate(
                todo: todo,
                categoryName: categoryName(for: todo.categoryId)
            )
        }
    }

    private func endActiveTask(_ todo: Todo) {
        taskControlError = nil
        todo.status = .open
        todo.updatedAt = Date()

        guard saveTodoChanges() else { return }
        reloadWidgetTimelines()

        Task { @MainActor in
            taskControlMessage = await LisdoActiveTaskActivityController.end(
                todo: todo,
                categoryName: categoryName(for: todo.categoryId)
            )
        }
    }

    private func completeTodo(_ todo: Todo) {
        taskControlError = nil
        todo.status = .completed
        todo.updatedAt = Date()
        todo.blocks?.forEach { block in
            block.checked = true
        }

        guard saveTodoChanges() else { return }
        reloadWidgetTimelines()

        Task { @MainActor in
            taskControlMessage = await LisdoActiveTaskActivityController.end(
                todo: todo,
                categoryName: categoryName(for: todo.categoryId)
            )
        }
    }

    private func toggleTodoCompletion(_ todo: Todo) {
        taskControlError = nil
        CaptureBatchActions.toggleSavedTodoCompletion(todo)

        guard saveTodoChanges() else { return }
        reloadWidgetTimelines()

        if todo.status == .completed {
            Task { @MainActor in
                taskControlMessage = await LisdoActiveTaskActivityController.end(
                    todo: todo,
                    categoryName: categoryName(for: todo.categoryId)
                )
            }
        } else {
            taskControlMessage = "Todo reopened."
        }
    }

    private func toggleTodoBlock(_ block: TodoBlock, in todo: Todo) {
        guard block.type == .checkbox else { return }

        taskControlError = nil
        block.checked.toggle()
        if todo.status == .completed && !block.checked {
            todo.status = .open
        }
        todo.updatedAt = Date()

        guard saveTodoChanges() else { return }
        reloadWidgetTimelines()
        taskControlMessage = block.checked ? "Checklist item completed." : "Checklist item reopened."
    }

    private func deleteTodo(_ todo: Todo) {
        taskControlError = nil
        TodoTrashPolicy.moveToTrash([todo])

        guard saveTodoChanges() else { return }
        Task { @MainActor in
            await LisdoReminderNotificationScheduler.syncNotifications(for: todo)
        }
        reloadWidgetTimelines()
        taskControlMessage = "Todo moved to Trash."
    }

    private func saveTodoChanges() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            taskControlError = "Lisdo could not save this approved todo update. Try again after iCloud finishes syncing."
            return false
        }
    }

    private func reloadWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

private struct TodoDetailSelection: Identifiable, Hashable {
    let todoID: UUID
    var id: UUID { todoID }
}

private struct MissingTodoDetailView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.badge.xmark")
                    .font(.system(size: 30))
                    .foregroundStyle(LisdoTheme.ink3)
                Text("Todo unavailable")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(LisdoTheme.ink1)
                Text("This todo may have been deleted or synced away on another device.")
                    .font(.callout)
                    .foregroundStyle(LisdoTheme.ink3)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LisdoTheme.surface)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct InboxFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedCaptureStatus: CaptureStatus?
    @Binding var selectedCategoryId: String?
    @Binding var selectedTodoStatus: TodoStatus?
    @Binding var selectedPriority: TodoPriority?

    var categories: [Category]
    var onClear: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Capture") {
                    Picker("Status", selection: $selectedCaptureStatus) {
                        Text("Any").tag(nil as CaptureStatus?)
                        ForEach(CaptureStatus.allCases, id: \.self) { status in
                            Text(status.rawValue.readableEnumLabel).tag(Optional(status))
                        }
                    }
                }

                Section("Todo") {
                    Picker("Category", selection: $selectedCategoryId) {
                        Text("Any").tag(nil as String?)
                        ForEach(categories, id: \.id) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }

                    Picker("Status", selection: $selectedTodoStatus) {
                        Text("Any").tag(nil as TodoStatus?)
                        ForEach(TodoStatus.allCases, id: \.self) { status in
                            Text(status.rawValue.readableEnumLabel).tag(Optional(status))
                        }
                    }

                    Picker("Priority", selection: $selectedPriority) {
                        Text("Any").tag(nil as TodoPriority?)
                        ForEach(TodoPriority.allCases, id: \.self) { priority in
                            Text(priority.rawValue.readableEnumLabel).tag(Optional(priority))
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        onClear()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct BatchActionButton: View {
    var title: String
    var systemImage: String
    var isProminent: Bool
    var isDisabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(borderColor, lineWidth: 1)
            }
            .opacity(isDisabled ? 0.46 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var foregroundColor: Color {
        if isDisabled { return LisdoTheme.ink4 }
        return isProminent ? LisdoTheme.onAccent : LisdoTheme.ink1
    }

    private var backgroundColor: Color {
        if isDisabled { return LisdoTheme.surface3.opacity(0.68) }
        return isProminent ? LisdoTheme.ink1 : LisdoTheme.surface3.opacity(0.72)
    }

    private var borderColor: Color {
        if isDisabled { return LisdoTheme.divider.opacity(0.5) }
        return isProminent ? LisdoTheme.ink1 : LisdoTheme.divider.opacity(0.85)
    }
}

struct DraftCardView: View {
    var draft: ProcessingDraft
    var categoryName: String
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(draft.generatedByProvider.isEmpty ? "Review draft" : draft.generatedByProvider, systemImage: "doc.text.viewfinder")
                        .font(.system(size: 11))
                        .foregroundStyle(LisdoTheme.ink3)
                    Spacer()
                    LisdoDraftChip()
                }

                HStack(spacing: 7) {
                    LisdoCategoryDot(categoryId: draft.recommendedCategoryId)
                    Text(categoryName.uppercased())
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.6)
                        .foregroundStyle(LisdoTheme.ink2)
                    Text("suggested")
                        .font(.system(size: 11))
                        .foregroundStyle(LisdoTheme.ink4)
                }

                Text(draft.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LisdoTheme.ink1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let summary = draft.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .foregroundStyle(LisdoTheme.ink3)
                }

                if !draft.blocks.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(draft.blocks.sorted { $0.order < $1.order }.prefix(4), id: \.self) { block in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle()
                                    .stroke(style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                                    .foregroundStyle(LisdoTheme.ink1.opacity(0.35))
                                    .frame(width: 14, height: 14)
                                Text(block.content)
                                    .font(.system(size: 13))
                                    .foregroundStyle(LisdoTheme.ink2)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .lisdoDashedDraft()
        }
        .buttonStyle(.plain)
    }
}

struct PendingCaptureRow: View {
    var capture: CaptureItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .frame(width: 30, height: 30)
                .background(LisdoTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(LisdoTheme.divider, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(preview)
                    .font(.system(size: 13))
                    .foregroundStyle(LisdoTheme.ink1)
                    .lineLimit(1)
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(statusColor)
            }

            Spacer()
        }
        .padding(12)
        .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(LisdoTheme.divider.opacity(0.7), lineWidth: 1)
        }
    }

    private var icon: String {
        switch capture.sourceType {
        case .photoImport, .cameraImport, .screenshotImport:
            "photo"
        case .voiceNote:
            "mic"
        case .shareExtension:
            "square.and.arrow.down"
        case .clipboard:
            "doc.on.clipboard"
        case .macScreenRegion:
            "rectangle.dashed"
        case .textPaste:
            "text.alignleft"
        }
    }

    private var preview: String {
        capture.sourceText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        ?? capture.transcriptText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        ?? capture.processingError
        ?? "Captured item"
    }

    private var statusText: String {
        switch capture.status {
        case .rawCaptured:
            "Captured. Waiting for text extraction."
        case .pendingProcessing:
            capture.preferredProviderMode == .macOnlyCLI
                ? "Waiting for Mac CLI."
                : "Ready for API processing."
        case .processing:
            "Processing into a draft."
        case .processedDraft:
            "Draft is ready to review."
        case .approvedTodo:
            "Saved as todo."
        case .failed:
            capture.processingError ?? "Processing failed."
        case .retryPending:
            "Ready to retry."
        }
    }

    private var statusColor: Color {
        switch capture.status {
        case .failed:
            LisdoTheme.warn
        case .processedDraft:
            LisdoTheme.ok
        default:
            LisdoTheme.ink3
        }
    }
}

struct TodoCardView: View {
    var todo: Todo
    var categoryName: String
    var showsActiveTaskControls = false
    var liveActivityDisabledText: String? = nil
    var onOpen: () -> Void = {}
    var onStart: () -> Void = {}
    var onAdvanceStep: () -> Void = {}
    var onEnd: () -> Void = {}
    var onComplete: () -> Void = {}
    var onToggleBlock: ((TodoBlock) -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    onOpen()
                } label: {
                    TodoStatusMark(status: todo.status)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open todo")
                .padding(.top, -3)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        LisdoCategoryDot(categoryId: todo.categoryId)
                        Text(categoryName.uppercased())
                            .font(.system(size: 10, weight: .medium))
                            .tracking(0.6)
                            .foregroundStyle(LisdoTheme.ink3)
                        if let due = todo.dueDateText {
                            Text(due)
                                .font(.system(size: 11))
                                .foregroundStyle(LisdoTheme.ink3)
                        }
                    }

                    Text(todo.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LisdoTheme.ink1)

                    if let summary = todo.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.system(size: 13))
                            .lineSpacing(3)
                            .foregroundStyle(LisdoTheme.ink3)
                    }
                }

                Spacer(minLength: 0)
            }

            let blocks = todo.blocks?.sortedForInboxDisplay() ?? []
            if !blocks.isEmpty {
                TodoBlockList(blocks: blocks, onToggleBlock: onToggleBlock)
            }

            let reminders = todo.reminders?.sortedForInboxReminders() ?? []
            if !reminders.isEmpty {
                TodoReminderList(reminders: reminders)
            }

            if showsActiveTaskControls && (todo.status == .open || todo.status == .inProgress) {
                TodoActiveTaskControls(
                    todo: todo,
                    liveActivityDisabledText: liveActivityDisabledText,
                    onStart: onStart,
                    onAdvanceStep: onAdvanceStep,
                    onEnd: onEnd,
                    onComplete: onComplete
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lisdoCard()
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button(action: onStart) {
                Label("Start focus", systemImage: "timer")
            }

            Button(action: onOpen) {
                Label("Edit", systemImage: "pencil")
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

struct CompactTodoCardView: View {
    var todo: Todo
    var categoryName: String
    var onOpen: () -> Void = {}
    var onStartFocus: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            TodoStatusMark(status: todo.status)
                .frame(width: 22, height: 22)
                .padding(.top, 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    LisdoCategoryDot(categoryId: todo.categoryId)
                    Text(categoryName.uppercased())
                        .tracking(0.6)
                    if let dateLabel {
                        CompactMetadataDivider()
                        Text(dateLabel)
                    }
                    if let priority = todo.priority {
                        CompactMetadataDivider()
                        Text(priorityLabel(priority))
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(LisdoTheme.ink3)
                .lineLimit(1)

                Text(todo.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LisdoTheme.ink1)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let summary = todo.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                    Text(summary)
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .foregroundStyle(LisdoTheme.ink3)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lisdoCard(padding: 13)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onOpen)
        .contextMenu {
            if let onStartFocus {
                Button(action: onStartFocus) {
                    Label("Start focus", systemImage: "timer")
                }
            }

            Button(action: onOpen) {
                Label("Edit", systemImage: "pencil")
            }

            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var dateLabel: String? {
        if let scheduledDate = todo.scheduledDate {
            return "Scheduled \(dateLabel(for: scheduledDate))"
        }
        if let dueDate = todo.dueDate {
            return "Due \(dateLabel(for: dueDate))"
        }
        return todo.dueDateText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func dateLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let includesTime = calendar.component(.hour, from: date) != 0
            || calendar.component(.minute, from: date) != 0

        if calendar.isDateInToday(date) {
            return includesTime ? "today, \(date.formatted(.dateTime.hour().minute()))" : "today"
        }
        if calendar.isDateInTomorrow(date) {
            return includesTime ? "tomorrow, \(date.formatted(.dateTime.hour().minute()))" : "tomorrow"
        }
        return includesTime
            ? date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
            : date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func priorityLabel(_ priority: TodoPriority) -> String {
        switch priority {
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        }
    }
}

private struct CompactMetadataDivider: View {
    var body: some View {
        Circle()
            .fill(LisdoTheme.ink5)
            .frame(width: 3, height: 3)
    }
}

private struct TodoBlockList: View {
    var blocks: [TodoBlock]
    var onToggleBlock: ((TodoBlock) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(blocks, id: \.id) { block in
                TodoBlockRow(block: block, onToggle: onToggleBlock)
            }
        }
        .padding(10)
        .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(LisdoTheme.divider.opacity(0.75), lineWidth: 1)
        }
    }
}

private struct TodoBlockRow: View {
    var block: TodoBlock
    var onToggle: ((TodoBlock) -> Void)?

    var body: some View {
        switch block.type {
        case .checkbox:
            Button {
                onToggle?(block)
            } label: {
                rowLabel {
                    TodoBlockCheckMark(isChecked: block.checked)
                }
            }
            .buttonStyle(.plain)
            .disabled(onToggle == nil)
            .accessibilityLabel(block.checked ? "Reopen checklist item" : "Complete checklist item")
        case .bullet:
            rowLabel {
                BulletGlyph()
            }
        case .note:
            rowLabel {
                NoteGlyph()
            }
        }
    }

    private func rowLabel<Icon: View>(@ViewBuilder icon: () -> Icon) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            icon()
                .frame(width: 18)
            Text(block.content)
                .font(.system(size: 13))
                .foregroundStyle(textColor)
                .strikethrough(block.type == .checkbox && block.checked, color: LisdoTheme.ink4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    private var textColor: Color {
        if block.type == .checkbox && block.checked {
            return LisdoTheme.ink3
        }
        return LisdoTheme.ink2
    }
}

private struct TodoBlockCheckMark: View {
    var isChecked: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(isChecked ? LisdoTheme.ink1 : LisdoTheme.ink5, lineWidth: 1.2)
                .frame(width: 16, height: 16)

            if isChecked {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(LisdoTheme.onAccent)
                    .frame(width: 16, height: 16)
                    .background(LisdoTheme.ink1, in: Circle())
            }
        }
        .accessibilityHidden(true)
    }
}

private struct BulletGlyph: View {
    var body: some View {
        Circle()
            .fill(LisdoTheme.ink4)
            .frame(width: 4, height: 4)
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }
}

private struct NoteGlyph: View {
    var body: some View {
        Image(systemName: "note.text")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(LisdoTheme.ink4)
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }
}

private struct TodoReminderList: View {
    var reminders: [TodoReminder]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "bell")
                    .font(.system(size: 11, weight: .medium))
                Text("Reminders")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.6)
            }
            .foregroundStyle(LisdoTheme.ink3)

            ForEach(reminders, id: \.id) { reminder in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "bell")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(reminder.isCompleted ? LisdoTheme.ink4 : LisdoTheme.ink2)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(reminder.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(reminder.isCompleted ? LisdoTheme.ink3 : LisdoTheme.ink1)
                        if let detail = reminderDetail(reminder) {
                            Text(detail)
                                .font(.system(size: 11))
                                .foregroundStyle(LisdoTheme.ink3)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(LisdoTheme.divider.opacity(0.75), lineWidth: 1)
        }
    }

    private func reminderDetail(_ reminder: TodoReminder) -> String? {
        [reminder.reminderDateText, reminder.reason]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .joined(separator: " · ")
            .nilIfEmpty
    }
}

struct TodoStatusMark: View {
    var status: TodoStatus

    var body: some View {
        ZStack {
            Circle()
                .stroke(status == .inProgress ? LisdoTheme.ink1 : LisdoTheme.ink5, lineWidth: 1.4)
                .frame(width: 18, height: 18)

            switch status {
            case .inProgress:
                Circle()
                    .fill(LisdoTheme.ink1)
                    .frame(width: 7, height: 7)
            case .completed:
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(LisdoTheme.onAccent)
                    .frame(width: 18, height: 18)
                    .background(LisdoTheme.ink1, in: Circle())
            case .open, .archived, .trashed:
                EmptyView()
            }
        }
        .accessibilityHidden(true)
    }
}

private struct TodoActiveTaskControls: View {
    var todo: Todo
    var liveActivityDisabledText: String?
    var onStart: () -> Void
    var onAdvanceStep: () -> Void
    var onEnd: () -> Void
    var onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if todo.status == .inProgress {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "livephoto")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LisdoTheme.ink3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(progressText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(LisdoTheme.ink3)
                        Text(currentStepText)
                            .font(.system(size: 12))
                            .foregroundStyle(LisdoTheme.ink2)
                            .lineLimit(2)
                    }
                }
            }

            HStack(spacing: 8) {
                if todo.status == .open {
                    Button(action: onStart) {
                        Label("Start", systemImage: "play.fill")
                    }
                    .buttonStyle(LisdoInlineControlStyle(filled: true))
                } else {
                    Button(action: onAdvanceStep) {
                        Label("Advance", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(LisdoInlineControlStyle())

                    Button(action: onEnd) {
                        Label("End", systemImage: "pause")
                    }
                    .buttonStyle(LisdoInlineControlStyle())
                }

                Button(action: onComplete) {
                    Label("Complete", systemImage: "checkmark")
                }
                .buttonStyle(LisdoInlineControlStyle())
            }

            if let liveActivityDisabledText {
                Text(liveActivityDisabledText)
                    .font(.system(size: 11))
                    .foregroundStyle(LisdoTheme.ink3)
                    .lineLimit(2)
            }
        }
        .padding(.top, 2)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LisdoTheme.divider.opacity(0.7))
                .frame(height: 1)
                .offset(y: -6)
        }
    }

    private var sortedBlocks: [TodoBlock] {
        (todo.blocks ?? []).sortedForInboxTaskControls()
    }

    private var currentStepText: String {
        todo.currentWidgetStep?.content ?? (sortedBlocks.isEmpty ? "No steps added." : "All steps are checked.")
    }

    private var progressText: String {
        guard !sortedBlocks.isEmpty else {
            return "No steps"
        }

        let checkedCount = sortedBlocks.filter(\.checked).count
        if checkedCount == sortedBlocks.count {
            return "All \(checkedCount) steps complete"
        }

        return "Step \(checkedCount + 1) of \(sortedBlocks.count)"
    }
}

private struct LisdoInlineControlStyle: ButtonStyle {
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(filled ? LisdoTheme.onAccent : LisdoTheme.ink1)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(filled ? LisdoTheme.ink1 : LisdoTheme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(filled ? LisdoTheme.ink1 : LisdoTheme.divider, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct ProductStateRow: View {
    var icon: String
    var title: String
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(LisdoTheme.ink3)
                .frame(width: 28, height: 28)
                .background(LisdoTheme.surface3, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LisdoTheme.ink1)
                Text(message)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundStyle(LisdoTheme.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lisdoCard(padding: 12)
    }
}

private extension Todo {
    var currentWidgetStep: TodoBlock? {
        (blocks ?? [])
            .sortedForInboxTaskControls()
            .first { !$0.checked }
    }
}

private extension Array where Element == TodoBlock {
    func sortedForInboxDisplay() -> [TodoBlock] {
        sortedForInboxBlocks()
    }

    func sortedForInboxTaskControls() -> [TodoBlock] {
        sortedForInboxBlocks().filter { $0.type == .checkbox }
    }

    private func sortedForInboxBlocks() -> [TodoBlock] {
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

private extension Array where Element == TodoReminder {
    func sortedForInboxReminders() -> [TodoReminder] {
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

private extension Error {
    var lisdoInboxUserMessage: String {
        if let localizedError = self as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return localizedDescription.isEmpty ? String(describing: self) : localizedDescription
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var readableEnumLabel: String {
        unicodeScalars.reduce(into: "") { result, scalar in
            let character = Character(scalar)
            if CharacterSet.uppercaseLetters.contains(scalar), !result.isEmpty {
                result.append(" ")
            }
            result.append(character)
        }
        .capitalized
    }
}
