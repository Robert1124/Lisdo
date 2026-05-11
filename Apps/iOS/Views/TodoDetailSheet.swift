import LisdoCore
import SwiftData
import SwiftUI

struct TodoDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var todo: Todo
    var categories: [Category]
    var openPomodoro: (Todo) -> Void = { _ in }

    @State private var isEditing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summarySection
                    checklistSection
                    remindersSection
                    actionSection

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(LisdoTheme.warn)
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(LisdoTheme.surface)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Todo")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onDisappear {
            if isEditing {
                saveChanges()
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    toggleCompletion()
                } label: {
                    TodoStatusMark(status: todo.status)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 8) {
                    if isEditing {
                        TextField("Todo title", text: titleBinding, axis: .vertical)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(LisdoTheme.ink1)
                            .textFieldStyle(.plain)
                    } else {
                        Text(todo.title)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(LisdoTheme.ink1)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isEditing || todo.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        if isEditing {
                            TextField("Summary", text: summaryBinding, axis: .vertical)
                                .font(.system(size: 14))
                                .foregroundStyle(LisdoTheme.ink2)
                                .textFieldStyle(.plain)
                        } else if let summary = todo.summary {
                            Text(summary)
                                .font(.system(size: 14))
                                .foregroundStyle(LisdoTheme.ink3)
                                .lineSpacing(3)
                        }
                    }
                }
            }

            metadataEditor
        }
        .lisdoCard(padding: 14)
    }

    @ViewBuilder
    private var metadataEditor: some View {
        if isEditing {
            VStack(alignment: .leading, spacing: 10) {
                LisdoSectionHeader(title: "Category")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.id) { category in
                            Button {
                                todo.categoryId = category.id
                            } label: {
                                HStack(spacing: 6) {
                                    LisdoCategoryDot(categoryId: category.id)
                                    Text(category.name)
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(todo.categoryId == category.id ? LisdoTheme.onAccent : LisdoTheme.ink2)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(todo.categoryId == category.id ? LisdoTheme.ink1 : LisdoTheme.surface2, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                LisdoSectionHeader(title: "Priority")
                HStack(spacing: 8) {
                    priorityButton(nil, title: "None")
                    priorityButton(.low, title: "Low")
                    priorityButton(.medium, title: "Medium")
                    priorityButton(.high, title: "High")
                }

                LisdoSectionHeader(title: "Date")
                LisdoSegmentedControl(
                    selection: dateModeBinding,
                    options: TodoDetailDateMode.allCases.map { ($0, $0.title) }
                )

                if currentDateMode != .none {
                    DatePicker(
                        currentDateMode == .due ? "Due date" : "Scheduled time",
                        selection: todoDateBinding,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    .foregroundStyle(LisdoTheme.ink2)
                }

                TextField("Original date phrase, optional", text: dueDateTextBinding, axis: .vertical)
                    .font(.system(size: 13))
                    .foregroundStyle(LisdoTheme.ink1)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(.top, 4)
        } else {
            HStack(spacing: 8) {
                LisdoCategoryDot(categoryId: todo.categoryId)
                Text(categoryName.uppercased())
                if let dateLabel {
                    Text("·")
                    Text(dateLabel)
                }
                if let priority = todo.priority {
                    Text("·")
                    Text(priorityLabel(priority))
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 11, weight: .medium))
            .tracking(0.5)
            .foregroundStyle(LisdoTheme.ink3)
        }
    }

    private func priorityButton(_ priority: TodoPriority?, title: String) -> some View {
        Button {
            todo.priority = priority
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(todo.priority == priority ? LisdoTheme.onAccent : LisdoTheme.ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(todo.priority == priority ? LisdoTheme.ink1 : LisdoTheme.surface2, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                LisdoSectionHeader(title: "Checklist", detail: "\(checkboxBlocks.filter(\.checked).count)/\(checkboxBlocks.count)")
                if isEditing {
                    Button {
                        addChecklistItem()
                    } label: {
                        Label("Add", systemImage: "plus")
                            .labelStyle(.titleAndIcon)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LisdoTheme.ink1)
                    .buttonStyle(.plain)
                }
            }

            if sortedBlocks.isEmpty {
                Text("No checklist items.")
                    .font(.system(size: 13))
                    .foregroundStyle(LisdoTheme.ink3)
            } else {
                ForEach(sortedBlocks, id: \.id) { block in
                    if isEditing {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Button {
                                toggleBlock(block)
                            } label: {
                                TodoDetailCheckMark(isChecked: block.checked)
                                    .frame(width: 20, height: 20)
                                    .alignmentGuide(.firstTextBaseline) { dimensions in
                                        dimensions[VerticalAlignment.center] + 2
                                    }
                            }
                            .buttonStyle(.plain)
                            .alignmentGuide(.firstTextBaseline) { dimensions in
                                dimensions[VerticalAlignment.center] + 2
                            }
                            .disabled(block.type != .checkbox)

                            TextField("Checklist item", text: blockContentBinding(block), axis: .vertical)
                                .font(.system(size: 14))
                                .foregroundStyle(LisdoTheme.ink1)
                                .textFieldStyle(.plain)
                                .padding(9)
                                .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                            LisdoInlineDeleteButton(
                                accessibilityLabel: "Delete checklist item",
                                action: { deleteBlock(block) }
                            )
                            .alignmentGuide(.firstTextBaseline) { dimensions in
                                dimensions[VerticalAlignment.center] + 2
                            }
                        }
                    } else {
                        Button {
                            toggleBlock(block)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                TodoDetailCheckMark(isChecked: block.checked)
                                    .frame(width: 20, height: 20)
                                    .alignmentGuide(.firstTextBaseline) { dimensions in
                                        dimensions[VerticalAlignment.center] + 2
                                    }

                                Text(block.content)
                                    .font(.system(size: 14))
                                    .foregroundStyle(block.checked ? LisdoTheme.ink3 : LisdoTheme.ink2)
                                    .strikethrough(block.checked, color: LisdoTheme.ink4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(block.type != .checkbox)
                    }
                }
            }
        }
        .lisdoCard(padding: 14)
    }

    @ViewBuilder
    private var remindersSection: some View {
        let reminders = sortedReminders
        if !reminders.isEmpty || isEditing {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    LisdoSectionHeader(title: "Reminders")
                    if isEditing {
                        Button {
                            addReminder()
                        } label: {
                            Label("Add", systemImage: "plus")
                                .labelStyle(.titleAndIcon)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LisdoTheme.ink1)
                        .buttonStyle(.plain)
                    }
                }

                if reminders.isEmpty {
                    Text("No reminders.")
                        .font(.system(size: 13))
                        .foregroundStyle(LisdoTheme.ink3)
                } else {
                    ForEach(reminders, id: \.id) { reminder in
                        if isEditing {
                            HStack(alignment: .top, spacing: 10) {
                                Button {
                                    toggleReminder(reminder)
                                } label: {
                                    TodoDetailCheckMark(isChecked: reminder.isCompleted)
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 8)

                                VStack(alignment: .leading, spacing: 8) {
                                    TextField("Reminder title", text: reminderTitleBinding(reminder), axis: .vertical)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(LisdoTheme.ink1)
                                        .textFieldStyle(.plain)
                                        .padding(9)
                                        .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                                    TextField("Reason, optional", text: reminderReasonBinding(reminder), axis: .vertical)
                                        .font(.system(size: 13))
                                        .foregroundStyle(LisdoTheme.ink2)
                                        .textFieldStyle(.plain)
                                        .padding(9)
                                        .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                                    TextField("Date phrase, optional", text: reminderDateTextBinding(reminder), axis: .vertical)
                                        .font(.system(size: 13))
                                        .foregroundStyle(LisdoTheme.ink2)
                                        .textFieldStyle(.plain)
                                        .padding(9)
                                        .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                                    LisdoCompactToggle(
                                        title: "Concrete reminder time",
                                        isOn: reminderHasDateBinding(reminder)
                                    )

                                    if reminder.reminderDate != nil {
                                        HStack(spacing: 8) {
                                            Text("Notify at")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(LisdoTheme.ink2)
                                            Spacer(minLength: 8)
                                            DatePicker(
                                                "",
                                                selection: reminderDateBinding(reminder),
                                                displayedComponents: [.date, .hourAndMinute]
                                            )
                                            .labelsHidden()
                                            .datePickerStyle(.compact)
                                            .controlSize(.small)
                                            .scaleEffect(0.86, anchor: .trailing)
                                            .frame(maxWidth: 210, alignment: .trailing)
                                        }
                                    }
                                }

                                LisdoInlineDeleteButton(
                                    accessibilityLabel: "Delete reminder",
                                    action: { deleteReminder(reminder) }
                                )
                                .padding(.top, 3)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(reminder.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(LisdoTheme.ink2)
                                if let detail = reminderDetail(reminder) {
                                    Text(detail)
                                        .font(.system(size: 12))
                                        .foregroundStyle(LisdoTheme.ink3)
                                }
                            }
                        }
                    }
                }
            }
            .lisdoCard(padding: 14)
        }
    }

    private var actionSection: some View {
        HStack(spacing: 10) {
            Button {
                openPomodoro(todo)
                dismiss()
            } label: {
                Label(todo.status == .inProgress ? "Open focus" : "Start focus", systemImage: "timer")
            }
            .buttonStyle(LisdoTonalButtonStyle())

            Button {
                if isEditing {
                    saveChanges()
                }
                withAnimation(.snappy(duration: 0.18)) {
                    isEditing.toggle()
                }
            } label: {
                Label(isEditing ? "Done" : "Edit", systemImage: isEditing ? "checkmark" : "pencil")
            }
            .buttonStyle(LisdoTonalButtonStyle(isProminent: true))

            Button(role: .destructive) {
                deleteTodo()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(LisdoTonalButtonStyle())
        }
    }

    private var titleBinding: Binding<String> {
        Binding {
            todo.title
        } set: { newValue in
            todo.title = newValue
            todo.updatedAt = Date()
        }
    }

    private var summaryBinding: Binding<String> {
        Binding {
            todo.summary ?? ""
        } set: { newValue in
            todo.summary = newValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            todo.updatedAt = Date()
        }
    }

    private var dueDateTextBinding: Binding<String> {
        Binding {
            todo.dueDateText ?? ""
        } set: { newValue in
            todo.dueDateText = newValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            todo.updatedAt = Date()
        }
    }

    private var dateModeBinding: Binding<TodoDetailDateMode> {
        Binding {
            currentDateMode
        } set: { newMode in
            switch newMode {
            case .none:
                todo.dueDate = nil
                todo.scheduledDate = nil
            case .due:
                todo.dueDate = todo.dueDate ?? todo.scheduledDate ?? Date()
                todo.scheduledDate = nil
            case .scheduled:
                todo.scheduledDate = todo.scheduledDate ?? todo.dueDate ?? Date()
                todo.dueDate = nil
            }
            todo.updatedAt = Date()
        }
    }

    private var todoDateBinding: Binding<Date> {
        Binding {
            todo.scheduledDate ?? todo.dueDate ?? Date()
        } set: { newDate in
            switch currentDateMode {
            case .none:
                todo.dueDate = newDate
                todo.scheduledDate = nil
            case .due:
                todo.dueDate = newDate
                todo.scheduledDate = nil
            case .scheduled:
                todo.scheduledDate = newDate
                todo.dueDate = nil
            }
            todo.updatedAt = Date()
        }
    }

    private var currentDateMode: TodoDetailDateMode {
        if todo.scheduledDate != nil {
            return .scheduled
        }
        if todo.dueDate != nil {
            return .due
        }
        return .none
    }

    private var dateLabel: String? {
        if let scheduledDate = todo.scheduledDate {
            return "Scheduled \(scheduledDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
        }
        if let dueDate = todo.dueDate {
            return "Due \(dueDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
        }
        return todo.dueDateText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private var categoryName: String {
        categories.first(where: { $0.id == todo.categoryId })?.name ?? "Inbox"
    }

    private var sortedBlocks: [TodoBlock] {
        (todo.blocks ?? []).sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private var checkboxBlocks: [TodoBlock] {
        sortedBlocks.filter { $0.type == .checkbox }
    }

    private var sortedReminders: [TodoReminder] {
        (todo.reminders ?? []).sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func blockContentBinding(_ block: TodoBlock) -> Binding<String> {
        Binding {
            block.content
        } set: { newValue in
            block.content = newValue
            todo.updatedAt = Date()
        }
    }

    private func reminderTitleBinding(_ reminder: TodoReminder) -> Binding<String> {
        Binding {
            reminder.title
        } set: { newValue in
            reminder.title = newValue
            reminder.updatedAt = Date()
            todo.updatedAt = Date()
        }
    }

    private func reminderReasonBinding(_ reminder: TodoReminder) -> Binding<String> {
        Binding {
            reminder.reason ?? ""
        } set: { newValue in
            reminder.reason = newValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            reminder.updatedAt = Date()
            todo.updatedAt = Date()
        }
    }

    private func reminderDateTextBinding(_ reminder: TodoReminder) -> Binding<String> {
        Binding {
            reminder.reminderDateText ?? ""
        } set: { newValue in
            reminder.reminderDateText = newValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            reminder.updatedAt = Date()
            todo.updatedAt = Date()
        }
    }

    private func reminderHasDateBinding(_ reminder: TodoReminder) -> Binding<Bool> {
        Binding {
            reminder.reminderDate != nil
        } set: { hasDate in
            reminder.reminderDate = hasDate ? (reminder.reminderDate ?? Date()) : nil
            reminder.updatedAt = Date()
            todo.updatedAt = Date()
        }
    }

    private func reminderDateBinding(_ reminder: TodoReminder) -> Binding<Date> {
        Binding {
            reminder.reminderDate ?? Date()
        } set: { newDate in
            reminder.reminderDate = newDate
            reminder.updatedAt = Date()
            todo.updatedAt = Date()
        }
    }

    private func toggleCompletion() {
        CaptureBatchActions.toggleSavedTodoCompletion(todo)
        if todo.status == .completed {
            todo.blocks?.forEach { block in
                if block.type == .checkbox {
                    block.checked = true
                }
            }
        }
        saveChanges()
    }

    private func deleteTodo() {
        TodoTrashPolicy.moveToTrash([todo])

        do {
            try modelContext.save()
            Task { @MainActor in
                await LisdoReminderNotificationScheduler.syncNotifications(for: todo)
            }
            dismiss()
        } catch {
            errorMessage = "Could not delete todo: \(error.localizedDescription)"
        }
    }

    private func toggleBlock(_ block: TodoBlock) {
        guard block.type == .checkbox else { return }
        block.checked.toggle()
        if todo.status == .completed && !block.checked {
            todo.status = .open
        }
        todo.updatedAt = Date()
        saveChanges()
    }

    private func addChecklistItem() {
        let nextOrder = ((todo.blocks ?? []).map(\.order).max() ?? -1) + 1
        let block = TodoBlock(
            todoId: todo.id,
            todo: todo,
            type: .checkbox,
            content: "",
            checked: false,
            order: nextOrder
        )
        modelContext.insert(block)
        var blocks = todo.blocks ?? []
        blocks.append(block)
        todo.blocks = blocks
        todo.updatedAt = Date()
    }

    private func deleteBlock(_ block: TodoBlock) {
        var blocks = todo.blocks ?? []
        blocks.removeAll { $0.id == block.id }
        todo.blocks = blocks
        modelContext.delete(block)
        todo.updatedAt = Date()
        saveChanges()
    }

    private func addReminder() {
        let nextOrder = ((todo.reminders ?? []).map(\.order).max() ?? -1) + 1
        let reminder = TodoReminder(
            todoId: todo.id,
            todo: todo,
            title: "",
            reminderDateText: nil,
            reminderDate: nil,
            reason: nil,
            isCompleted: false,
            order: nextOrder
        )
        modelContext.insert(reminder)
        var reminders = todo.reminders ?? []
        reminders.append(reminder)
        todo.reminders = reminders
        todo.updatedAt = Date()
    }

    private func deleteReminder(_ reminder: TodoReminder) {
        var reminders = todo.reminders ?? []
        reminders.removeAll { $0.id == reminder.id }
        todo.reminders = reminders
        modelContext.delete(reminder)
        todo.updatedAt = Date()
        saveChanges()
    }

    private func toggleReminder(_ reminder: TodoReminder) {
        reminder.isCompleted.toggle()
        reminder.updatedAt = Date()
        todo.updatedAt = Date()
        saveChanges()
    }

    private func saveChanges() {
        todo.title = todo.title.trimmingCharacters(in: .whitespacesAndNewlines)
        todo.summary = todo.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let emptyBlocks = (todo.blocks ?? []).filter { $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        emptyBlocks.forEach { modelContext.delete($0) }
        todo.blocks = (todo.blocks ?? []).filter { block in
            !emptyBlocks.contains { $0.id == block.id }
        }
        todo.blocks?.forEach { block in
            block.content = block.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let emptyReminders = (todo.reminders ?? []).filter { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        emptyReminders.forEach { modelContext.delete($0) }
        todo.reminders = (todo.reminders ?? []).filter { reminder in
            !emptyReminders.contains { $0.id == reminder.id }
        }
        todo.reminders?.forEach { reminder in
            reminder.title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
            reminder.reason = reminder.reason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            reminder.reminderDateText = reminder.reminderDateText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        todo.updatedAt = Date()

        do {
            try modelContext.save()
            errorMessage = nil
        } catch {
            errorMessage = "Could not save todo changes: \(error.localizedDescription)"
        }
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

private struct TodoDetailCheckMark: View {
    var isChecked: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(isChecked ? LisdoTheme.ink1 : LisdoTheme.ink5, lineWidth: 1.2)
                .frame(width: 18, height: 18)

            if isChecked {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(LisdoTheme.onAccent)
                    .frame(width: 18, height: 18)
                    .background(LisdoTheme.ink1, in: Circle())
            }
        }
        .accessibilityHidden(true)
    }
}

private struct LisdoCompactToggle: View {
    var title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.16)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(LisdoTheme.ink2)
                Spacer(minLength: 8)
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? LisdoTheme.ink1 : LisdoTheme.surface3)
                        .overlay {
                            Capsule()
                                .stroke(LisdoTheme.divider.opacity(0.85), lineWidth: 1)
                        }
                    Circle()
                        .fill(isOn ? LisdoTheme.onAccent : LisdoTheme.ink4)
                        .frame(width: 18, height: 18)
                        .padding(3)
                }
                .frame(width: 44, height: 24)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private enum TodoDetailDateMode: String, CaseIterable, Identifiable {
    case none
    case due
    case scheduled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            "No date"
        case .due:
            "Due"
        case .scheduled:
            "Scheduled"
        }
    }
}
