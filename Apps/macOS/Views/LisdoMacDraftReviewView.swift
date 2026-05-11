import LisdoCore
import SwiftData
import SwiftUI

struct LisdoDraftReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var captures: [CaptureItem]

    let draft: ProcessingDraft
    let categories: [Category]

    @State private var title: String
    @State private var summary: String
    @State private var selectedCategoryId: String
    @State private var dueDateText: String
    @State private var dateMode: LisdoMacTodoDateMode
    @State private var selectedDate: Date
    @State private var priority: TodoPriority?
    @State private var blocks: [DraftBlock]
    @State private var suggestedReminders: [DraftReminderSuggestion]
    @State private var errorMessage: String?
    @State private var revisionInstructions = ""
    @State private var revisionStatus: String?
    @State private var isRevising = false

    init(draft: ProcessingDraft, categories: [Category]) {
        self.draft = draft
        self.categories = categories
        let fallbackCategory = categories.defaultCategoryId
        _title = State(initialValue: draft.title)
        _summary = State(initialValue: draft.summary ?? "")
        _selectedCategoryId = State(initialValue: draft.recommendedCategoryId ?? fallbackCategory)
        _dueDateText = State(initialValue: draft.dueDateText ?? "")
        if let scheduledDate = draft.scheduledDate {
            _dateMode = State(initialValue: .scheduled)
            _selectedDate = State(initialValue: scheduledDate)
        } else if let dueDate = draft.dueDate {
            _dateMode = State(initialValue: .due)
            _selectedDate = State(initialValue: dueDate)
        } else {
            _dateMode = State(initialValue: .none)
            _selectedDate = State(initialValue: Date())
        }
        _priority = State(initialValue: draft.priority)
        _blocks = State(initialValue: draft.blocks.sorted { $0.order < $1.order })
        _suggestedReminders = State(initialValue: draft.suggestedReminders.sorted { $0.order < $1.order })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 640, minHeight: 620)
        .alert("Could not save todo", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .frame(width: 30, height: 30)
                .background(LisdoMacTheme.ink1, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(LisdoMacTheme.onAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Review draft")
                    .font(.headline)
                Text("Edit every field before saving. Lisdo only creates a todo after this approval.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(18)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
                    GridRow {
                        Text("Category")
                            .font(.callout.weight(.medium))
                        Picker("Category", selection: $selectedCategoryId) {
                            ForEach(categories, id: \.id) { category in
                                Text(category.name).tag(category.id)
                            }
                        }
                        .labelsHidden()
                    }

                    GridRow {
                        Text("Priority")
                            .font(.callout.weight(.medium))
                        Picker("Priority", selection: $priority) {
                            Text("None").tag(Optional<TodoPriority>.none)
                            ForEach(TodoPriority.allCases, id: \.self) { priority in
                                Text(priority.rawValue.capitalized).tag(Optional(priority))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    GridRow {
                        Text("Date")
                            .font(.callout.weight(.medium))
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Date type", selection: $dateMode) {
                                ForEach(LisdoMacTodoDateMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .labelsHidden()
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
                            Text("Use the picker for the saved date. The original phrase is kept only as context from the draft.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Title")
                        .font(.callout.weight(.medium))
                    TextField("Draft title", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Summary")
                        .font(.callout.weight(.medium))
                    TextEditor(text: $summary)
                        .font(.body)
                        .frame(minHeight: 86)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(LisdoMacTheme.divider.opacity(0.78))
                        }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Checklist and notes")
                            .font(.callout.weight(.medium))
                        Spacer()
                        Button {
                            addBlock()
                        } label: {
                            Label("Add item", systemImage: "plus")
                        }
                    }

                    if blocks.isEmpty {
                        Text("No blocks yet. Add at least one item if this todo needs a checklist or note.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        ForEach(blocks.indices, id: \.self) { index in
                            blockRow(index)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Suggested reminders")
                            .font(.callout.weight(.medium))
                        Spacer()
                        Button {
                            addReminder()
                        } label: {
                            Label("Add reminder", systemImage: "bell.badge")
                        }
                    }

                    if suggestedReminders.isEmpty {
                        Text("No reminder suggestions. Add one if this todo needs a separate advance reminder after approval.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        ForEach(suggestedReminders.indices, id: \.self) { index in
                            reminderRow(index)
                        }
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        if draft.needsClarification {
                            Text(draft.questionsForUser.isEmpty ? "The provider marked this draft as needing clarification." : draft.questionsForUser.joined(separator: "\n"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        TextEditor(text: $revisionInstructions)
                            .font(.body)
                            .frame(minHeight: 72)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(LisdoMacTheme.divider.opacity(0.78))
                            }

                        HStack {
                            if let revisionStatus {
                                Text(revisionStatus)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                Task {
                                    await reviseDraft()
                                }
                            } label: {
                                Label(isRevising ? "Revising" : "Revise draft", systemImage: "sparkles")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRevising || revisionInstructions.lisdoTrimmed.isEmpty)
                        }
                    }
                    .padding(6)
                } label: {
                    Label("Revise with instructions", systemImage: "sparkles")
                }
            }
            .padding(20)
        }
        .background(LisdoMacTheme.surface)
    }

    private var footer: some View {
        HStack {
            Text("Draft remains editable until you approve it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Save as todo") {
                saveTodo()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(title.lisdoTrimmed.isEmpty || selectedCategoryId.lisdoTrimmed.isEmpty)
        }
        .padding(18)
    }

    private func blockRow(_ index: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Picker("Type", selection: Binding(
                get: { blocks[index].type },
                set: { blocks[index].type = $0 }
            )) {
                Text("Check").tag(TodoBlockType.checkbox)
                Text("Bullet").tag(TodoBlockType.bullet)
                Text("Note").tag(TodoBlockType.note)
            }
            .labelsHidden()
            .frame(width: 96)

            TextField("Item", text: Binding(
                get: { blocks[index].content },
                set: { blocks[index].content = $0 }
            ))
            .textFieldStyle(.roundedBorder)

            Button {
                blocks.remove(at: index)
                reorderBlocks()
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Remove item")
        }
    }

    private func addBlock() {
        blocks.append(DraftBlock(type: .checkbox, content: "", checked: false, order: blocks.count))
    }

    private func addReminder() {
        suggestedReminders.append(DraftReminderSuggestion(title: "", order: suggestedReminders.count))
    }

    private func reorderBlocks() {
        blocks = blocks.enumerated().map { index, block in
            var updated = block
            updated.order = index
            return updated
        }
    }

    private func reorderReminders() {
        suggestedReminders = suggestedReminders.enumerated().map { index, reminder in
            var updated = reminder
            updated.order = index
            return updated
        }
    }

    private func reminderRow(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Toggle("Include", isOn: Binding(
                    get: { suggestedReminders[index].defaultSelected },
                    set: { suggestedReminders[index].defaultSelected = $0 }
                ))
                .toggleStyle(.checkbox)
                .frame(width: 80, alignment: .leading)

                TextField("Reminder title", text: Binding(
                    get: { suggestedReminders[index].title },
                    set: { suggestedReminders[index].title = $0 }
                ))
                .textFieldStyle(.roundedBorder)

                Button {
                    suggestedReminders.remove(at: index)
                    reorderReminders()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Remove reminder")
            }

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Label("When", systemImage: "bell")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Natural language reminder time", text: Binding(
                        get: { suggestedReminders[index].reminderDateText ?? "" },
                        set: { suggestedReminders[index].reminderDateText = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Label("Notify", systemImage: "bell.badge")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Toggle("Notify", isOn: reminderNotificationBinding(at: index))
                            .toggleStyle(.checkbox)
                        if suggestedReminders[index].reminderDate != nil {
                            DatePicker(
                                "Notification time",
                                selection: reminderNotificationDateBinding(at: index),
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.compact)
                            .labelsHidden()
                        }
                    }
                }

                GridRow {
                    Label("Reason", systemImage: "text.quote")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Why this reminder helps", text: Binding(
                        get: { suggestedReminders[index].reason ?? "" },
                        set: { suggestedReminders[index].reason = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(10)
        .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(LisdoMacTheme.divider.opacity(0.78))
        }
    }

    private func saveTodo() {
        do {
            reorderBlocks()
            reorderReminders()
            draft.title = title.lisdoTrimmed
            draft.summary = summary.lisdoTrimmed.isEmpty ? nil : summary.lisdoTrimmed
            draft.recommendedCategoryId = selectedCategoryId
            syncDateEdits()
            draft.priority = priority
            draft.blocks = blocks
                .filter { !$0.content.lisdoTrimmed.isEmpty }
                .enumerated()
                .map { index, block in
                    DraftBlock(type: block.type, content: block.content.lisdoTrimmed, checked: block.checked, order: index)
                }
            draft.suggestedReminders = sanitizedReminders()

            let todo = try DraftApprovalConverter.convert(
                draft,
                categoryId: selectedCategoryId,
                approval: DraftApproval(approvedByUser: true)
            )
            modelContext.insert(todo)

            if let capture = captures.first(where: { $0.id == draft.captureItemId }),
               capture.status == .processedDraft {
                try? capture.transition(to: .approvedTodo)
            }

            modelContext.delete(draft)
            try modelContext.save()
            Task { @MainActor in
                await LisdoReminderNotificationScheduler.syncNotifications(for: todo)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func reviseDraft() async {
        guard !isRevising else { return }
        syncDraftEdits()

        isRevising = true
        revisionStatus = "Rerunning draft through the selected provider."
        defer { isRevising = false }

        let outcome = await LisdoMacMVP2Processing.reviseDraft(
            draft,
            capture: captures.first(where: { $0.id == draft.captureItemId }),
            revisionInstructions: revisionInstructions,
            selectedCategoryId: selectedCategoryId,
            categories: categories,
            modelContext: modelContext
        )

        revisionStatus = outcome.message
        if outcome.kind == .draftCreated {
            title = draft.title
            summary = draft.summary ?? ""
            selectedCategoryId = draft.recommendedCategoryId ?? categories.defaultCategoryId
            loadDateState(from: draft)
            priority = draft.priority
            blocks = draft.blocks.sorted { $0.order < $1.order }
            suggestedReminders = draft.suggestedReminders.sorted { $0.order < $1.order }
            revisionInstructions = ""
        }
    }

    private func syncDraftEdits() {
        reorderBlocks()
        reorderReminders()
        draft.title = title.lisdoTrimmed
        draft.summary = summary.lisdoTrimmed.isEmpty ? nil : summary.lisdoTrimmed
        draft.recommendedCategoryId = selectedCategoryId
        syncDateEdits()
        draft.priority = priority
        draft.blocks = blocks
            .filter { !$0.content.lisdoTrimmed.isEmpty }
            .enumerated()
            .map { index, block in
                DraftBlock(type: block.type, content: block.content.lisdoTrimmed, checked: block.checked, order: index)
            }
        draft.suggestedReminders = sanitizedReminders()
    }

    private func sanitizedReminders() -> [DraftReminderSuggestion] {
        suggestedReminders
            .filter { !$0.title.lisdoTrimmed.isEmpty }
            .enumerated()
            .map { index, reminder in
                DraftReminderSuggestion(
                    title: reminder.title.lisdoTrimmed,
                    reminderDateText: optionalTrimmed(reminder.reminderDateText),
                    reminderDate: reminder.reminderDate,
                    reason: optionalTrimmed(reminder.reason),
                    defaultSelected: reminder.defaultSelected,
                    order: index
                )
            }
    }

    private func optionalTrimmed(_ value: String?) -> String? {
        guard let trimmed = value?.lisdoTrimmed, !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func reminderNotificationBinding(at index: Int) -> Binding<Bool> {
        Binding {
            suggestedReminders[index].reminderDate != nil
        } set: { isEnabled in
            suggestedReminders[index].reminderDate = isEnabled ? (suggestedReminders[index].reminderDate ?? defaultReminderDate) : nil
        }
    }

    private func reminderNotificationDateBinding(at index: Int) -> Binding<Date> {
        Binding {
            suggestedReminders[index].reminderDate ?? defaultReminderDate
        } set: { newDate in
            suggestedReminders[index].reminderDate = newDate
        }
    }

    private var defaultReminderDate: Date {
        Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    }

    private func syncDateEdits() {
        draft.dueDateText = dueDateText.lisdoTrimmed.isEmpty ? nil : dueDateText.lisdoTrimmed
        switch dateMode {
        case .none:
            draft.dueDate = nil
            draft.scheduledDate = nil
        case .due:
            draft.dueDate = selectedDate
            draft.scheduledDate = nil
        case .scheduled:
            draft.dueDate = nil
            draft.scheduledDate = selectedDate
        }
    }

    private func loadDateState(from draft: ProcessingDraft) {
        dueDateText = draft.dueDateText ?? ""
        if let scheduledDate = draft.scheduledDate {
            dateMode = .scheduled
            selectedDate = scheduledDate
        } else if let dueDate = draft.dueDate {
            dateMode = .due
            selectedDate = dueDate
        } else {
            dateMode = .none
            selectedDate = Date()
        }
    }
}

enum LisdoMacTodoDateMode: String, CaseIterable, Identifiable {
    case none
    case due
    case scheduled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return "No date"
        case .due:
            return "Due"
        case .scheduled:
            return "Scheduled"
        }
    }
}
