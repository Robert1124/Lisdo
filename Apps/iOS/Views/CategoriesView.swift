import LisdoCore
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CategoriesView: View {
    @Environment(\.modelContext) private var modelContext

    var categories: [Category]
    var todos: [Todo]
    var drafts: [ProcessingDraft]
    var captures: [CaptureItem]
    var openPomodoro: (Todo) -> Void = { _ in }

    @State private var editingCategory: CategoryEditorState?
    @State private var categoryMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header
                createButton

                if let categoryMessage {
                    ProductStateRow(icon: "info.circle", title: "Category update", message: categoryMessage)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(categories, id: \.id) { category in
                        NavigationLink {
                            CategoryDetailView(
                                category: category,
                                todos: todosForCategory(category.id),
                                openPomodoro: openPomodoro
                            )
                        } label: {
                            CategoryTile(category: category, count: todosForCategory(category.id).count)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit") {
                                editingCategory = CategoryEditorState(category: category)
                            }
                            Button("Delete", role: .destructive) {
                                deleteCategory(category)
                            }
                            .disabled(!canDelete(category))
                        }
                    }
                }

                Section {
                    VStack(spacing: 0) {
                        SmartListRow(icon: "calendar", title: "Today", detail: "\(todayCount) due")
                        SmartListRow(icon: "sparkle", title: "AI Drafts", detail: "\(drafts.count) ready")
                        SmartListRow(icon: "tray", title: "Captured without draft", detail: "\(pendingCount) items")
                        SmartListRow(icon: "exclamationmark.circle", title: "Needs attention", detail: "\(failedCount) failed", showDivider: false)
                    }
                    .lisdoCard(padding: 0)
                } header: {
                    LisdoSectionHeader(title: "Smart lists")
                }
            }
            .padding(16)
        }
        .background(LisdoTheme.surface)
        .navigationTitle("Categories")
        .sheet(item: $editingCategory) { state in
            CategoryEditorView(
                state: state,
                canDelete: state.category.map(canDelete) ?? false,
                onSave: saveCategory,
                onDelete: { category in deleteCategory(category) }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Categories")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(LisdoTheme.ink1)
            Text("\(categories.count) active categories")
                .font(.system(size: 13))
                .foregroundStyle(LisdoTheme.ink3)
        }
        .padding(.horizontal, 4)
    }

    private var createButton: some View {
        Button {
            editingCategory = CategoryEditorState()
        } label: {
            Label("New category", systemImage: "plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(LisdoTheme.ink1)
    }

    private var todayCount: Int {
        todos.filter {
            Calendar.current.isDateInToday($0.dueDate ?? .distantPast)
            || Calendar.current.isDateInToday($0.scheduledDate ?? .distantPast)
            || ($0.dueDateText?.localizedCaseInsensitiveContains("today") == true)
        }.count
    }

    private var pendingCount: Int {
        captures.filter {
            switch $0.status {
            case .rawCaptured, .pendingProcessing, .processing, .failed, .retryPending:
                true
            case .processedDraft, .approvedTodo:
                false
            }
        }.count
    }

    private var failedCount: Int {
        captures.filter { $0.status == .failed }.count
    }

    private func todosForCategory(_ id: String) -> [Todo] {
        todos.filter { $0.categoryId == id }
    }

    private func canDelete(_ category: Category) -> Bool {
        !todos.contains { $0.categoryId == category.id }
            && !drafts.contains { $0.recommendedCategoryId == category.id }
    }

    private func deleteCategory(_ category: Category) {
        guard canDelete(category) else {
            categoryMessage = "Delete is disabled while todos or drafts still reference \(category.name). Move or approve those items first."
            return
        }

        modelContext.delete(category)
        do {
            try modelContext.save()
            categoryMessage = "\(category.name) was deleted."
        } catch {
            categoryMessage = "Could not delete \(category.name). Try again after sync finishes."
        }
    }

    private func saveCategory(_ state: CategoryEditorState) {
        let trimmedName = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            categoryMessage = "Category name is required."
            return
        }

        let trimmedIcon = state.icon.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if let trimmedIcon, !CategoryIconValidator.isValid(trimmedIcon) {
            categoryMessage = "\"\(trimmedIcon)\" is not an available SF Symbol. Choose an icon or correct the manual name."
            return
        }

        if let category = state.category {
            category.name = trimmedName
            category.descriptionText = state.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
            category.formattingInstruction = state.formattingInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
            category.schemaPreset = state.schemaPreset
            category.icon = trimmedIcon
            category.updatedAt = Date()
        } else {
            modelContext.insert(
                Category(
                    name: trimmedName,
                    descriptionText: state.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
                    formattingInstruction: state.formattingInstruction.trimmingCharacters(in: .whitespacesAndNewlines),
                    schemaPreset: state.schemaPreset,
                    icon: trimmedIcon
                )
            )
        }

        do {
            try modelContext.save()
            categoryMessage = "Category settings saved. Future drafts can use this instruction and schema preset."
            editingCategory = nil
        } catch {
            categoryMessage = "Could not save category. Try again after sync finishes."
        }
    }
}

struct CategoryEditorState: Identifiable {
    let id = UUID()
    var category: Category?
    var name: String
    var descriptionText: String
    var formattingInstruction: String
    var schemaPreset: CategorySchemaPreset
    var icon: String

    init(category: Category? = nil) {
        self.category = category
        name = category?.name ?? ""
        descriptionText = category?.descriptionText ?? ""
        formattingInstruction = category?.formattingInstruction ?? ""
        schemaPreset = category?.schemaPreset ?? .general
        icon = category?.icon ?? ""
    }
}

private struct CategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var state: CategoryEditorState
    @State private var usesCustomIcon: Bool
    var canDelete: Bool
    var onSave: (CategoryEditorState) -> Void
    var onDelete: (Category) -> Void

    init(
        state: CategoryEditorState,
        canDelete: Bool,
        onSave: @escaping (CategoryEditorState) -> Void,
        onDelete: @escaping (Category) -> Void
    ) {
        _state = State(initialValue: state)
        _usesCustomIcon = State(initialValue: CategoryIconPickerState.shouldUseCustomInput(for: state.icon))
        self.canDelete = canDelete
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Name", text: $state.name)
                    CategoryIconPicker(iconName: $state.icon, usesCustomIcon: $usesCustomIcon)
                }

                Section("Draft prompt") {
                    TextField("Description", text: $state.descriptionText, axis: .vertical)
                        .lineLimit(2...4)
                    Text("Description helps you understand what belongs in this category.")
                        .font(.footnote)
                        .foregroundStyle(LisdoTheme.ink3)
                    TextField("Instruction", text: $state.formattingInstruction, axis: .vertical)
                        .lineLimit(3...6)
                    Text("Instruction is sent to the AI provider as category-specific organizing guidance for drafts.")
                        .font(.footnote)
                        .foregroundStyle(LisdoTheme.ink3)
                }

                Section("Schema") {
                    Picker("Preset", selection: $state.schemaPreset) {
                        ForEach(CategorySchemaPreset.allCases, id: \.self) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                }

                if let category = state.category {
                    Section {
                        Button("Delete category", role: .destructive) {
                            onDelete(category)
                            dismiss()
                        }
                        .disabled(!canDelete)

                        if !canDelete {
                            Text("Delete is disabled while todos or drafts reference this category.")
                                .font(.footnote)
                                .foregroundStyle(LisdoTheme.ink3)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LisdoTheme.surface)
            .navigationTitle(state.category == nil ? "New category" : "Edit category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(state)
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        let hasName = !state.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasName && iconValidationMessage == nil
    }

    private var iconValidationMessage: String? {
        let trimmedIcon = state.icon.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIcon.isEmpty, !CategoryIconValidator.isValid(trimmedIcon) else {
            return nil
        }
        return "\"\(trimmedIcon)\" is not an available SF Symbol."
    }
}

private extension CategorySchemaPreset {
    var displayName: String {
        switch self {
        case .general: "General"
        case .checklist: "Checklist"
        case .shoppingList: "Shopping list"
        case .research: "Research"
        case .meeting: "Meeting"
        }
    }
}

private struct CategoryIconPicker: View {
    @Binding var iconName: String
    @Binding var usesCustomIcon: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Icon")
                    .font(.subheadline)
                    .foregroundStyle(LisdoTheme.ink1)
                Spacer()
                Button(usesCustomIcon ? "Use common" : "Customize") {
                    usesCustomIcon.toggle()
                }
                .font(.footnote.weight(.medium))
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(CategoryIconOption.common) { option in
                    Button {
                        iconName = option.name
                        usesCustomIcon = false
                    } label: {
                        Image(systemName: option.previewName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isSelected(option) ? LisdoTheme.onAccent : LisdoTheme.ink2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(isSelected(option) ? LisdoTheme.ink1 : LisdoTheme.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isSelected(option) ? LisdoTheme.ink1 : LisdoTheme.divider, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.accessibilityLabel)
                }
            }

            if usesCustomIcon {
                TextField("Symbol name", text: $iconName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(LisdoTheme.warn)
                } else {
                    Text("Enter an SF Symbol name, such as doc.text or lightbulb.")
                        .font(.footnote)
                        .foregroundStyle(LisdoTheme.ink3)
                }
            }
        }
        .onChange(of: usesCustomIcon) { _, isCustom in
            guard !isCustom else { return }
            if !CategoryIconOption.commonNames.contains(trimmedIconName) {
                iconName = ""
            }
        }
    }

    private var trimmedIconName: String {
        iconName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validationMessage: String? {
        guard !trimmedIconName.isEmpty, !CategoryIconValidator.isValid(trimmedIconName) else {
            return nil
        }
        return "\"\(trimmedIconName)\" is not an available SF Symbol."
    }

    private func isSelected(_ option: CategoryIconOption) -> Bool {
        trimmedIconName == option.name && !usesCustomIcon
    }
}

private struct CategoryIconOption: Identifiable {
    var id: String { name.isEmpty ? "default" : name }
    var name: String
    var previewName: String
    var accessibilityLabel: String

    static let common: [CategoryIconOption] = [
        CategoryIconOption(name: "", previewName: "square.grid.2x2", accessibilityLabel: "Default icon"),
        CategoryIconOption(name: "briefcase", previewName: "briefcase", accessibilityLabel: "Briefcase icon"),
        CategoryIconOption(name: "book", previewName: "book", accessibilityLabel: "Book icon"),
        CategoryIconOption(name: "bag", previewName: "bag", accessibilityLabel: "Bag icon"),
        CategoryIconOption(name: "person", previewName: "person", accessibilityLabel: "Person icon"),
        CategoryIconOption(name: "house", previewName: "house", accessibilityLabel: "House icon"),
        CategoryIconOption(name: "cart", previewName: "cart", accessibilityLabel: "Cart icon"),
        CategoryIconOption(name: "checklist", previewName: "checklist", accessibilityLabel: "Checklist icon"),
        CategoryIconOption(name: "calendar", previewName: "calendar", accessibilityLabel: "Calendar icon"),
        CategoryIconOption(name: "lightbulb", previewName: "lightbulb", accessibilityLabel: "Lightbulb icon"),
        CategoryIconOption(name: "doc.text", previewName: "doc.text", accessibilityLabel: "Document icon"),
        CategoryIconOption(name: "tray", previewName: "tray", accessibilityLabel: "Tray icon")
    ]

    static var commonNames: Set<String> {
        Set(common.map(\.name))
    }
}

private enum CategoryIconPickerState {
    static func shouldUseCustomInput(for iconName: String) -> Bool {
        let trimmedIconName = iconName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedIconName.isEmpty && !CategoryIconOption.commonNames.contains(trimmedIconName)
    }
}

private enum CategoryIconValidator {
    static func isValid(_ symbolName: String) -> Bool {
        let trimmedSymbolName = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSymbolName.isEmpty else { return true }

        #if canImport(UIKit)
        return UIImage(systemName: trimmedSymbolName) != nil
        #else
        return true
        #endif
    }
}

private struct CategoryTile: View {
    var category: Category
    var count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: iconName)
                    .font(.system(size: 15))
                    .frame(width: 30, height: 30)
                    .background(LisdoTheme.surface3, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer()
                Text("\(count)")
                    .font(.system(size: 12))
                    .foregroundStyle(LisdoTheme.ink3)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(category.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LisdoTheme.ink1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(LisdoTheme.ink3)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .lisdoCard()
    }

    private var subtitle: String {
        if !category.descriptionText.isEmpty {
            return category.descriptionText
        }
        return count == 1 ? "1 active todo" : "\(count) active todos"
    }

    private var iconName: String {
        if let icon = category.icon?.trimmingCharacters(in: .whitespacesAndNewlines),
           !icon.isEmpty,
           CategoryIconValidator.isValid(icon) {
            return icon
        }
        return "square.grid.2x2"
    }
}

private struct SmartListRow: View {
    var icon: String
    var title: String
    var detail: String
    var showDivider = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .frame(width: 28, height: 28)
                    .background(LisdoTheme.surface3, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LisdoTheme.ink1)
                Spacer()
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(LisdoTheme.ink3)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LisdoTheme.ink4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)

            if showDivider {
                Divider().padding(.leading, 54)
            }
        }
    }
}

private struct CategoryDetailView: View {
    @Environment(\.modelContext) private var modelContext

    var category: Category
    var todos: [Todo]
    var openPomodoro: (Todo) -> Void
    @State private var todoMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if let todoMessage {
                    ProductStateRow(icon: "checkmark.circle", title: "Todo update", message: todoMessage)
                }

                if todos.isEmpty {
                    ProductStateRow(
                        icon: "square.grid.2x2",
                        title: "No todos in \(category.name)",
                        message: "Approved drafts saved to this category will appear here."
                    )
                } else {
                    ForEach(todos, id: \.id) { todo in
                        TodoCardView(
                            todo: todo,
                            categoryName: category.name,
                            showsActiveTaskControls: true,
                            liveActivityDisabledText: LisdoPomodoroActivityController.disabledStatusText,
                            onStart: { openPomodoro(todo) },
                            onAdvanceStep: { advanceStep(todo) },
                            onEnd: { endFocus(todo) },
                            onComplete: { completeTodo(todo) },
                            onToggleCompletion: { toggleCompletion(todo) },
                            onToggleBlock: { block in toggleBlock(block, in: todo) },
                            onDelete: { deleteTodo(todo) }
                        )
                    }
                }
            }
            .padding(16)
        }
        .background(LisdoTheme.surface)
        .navigationTitle(category.name)
    }

    private func toggleCompletion(_ todo: Todo) {
        CaptureBatchActions.toggleSavedTodoCompletion(todo)

        do {
            try modelContext.save()
            todoMessage = todo.status == .completed ? "Completed todo." : "Reopened todo."
        } catch {
            todoMessage = "Could not update todo: \(error.localizedDescription)"
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
            todoMessage = block.checked ? "Completed checklist item." : "Reopened checklist item."
        } catch {
            todoMessage = "Could not update checklist item: \(error.localizedDescription)"
        }
    }

    private func advanceStep(_ todo: Todo) {
        guard let currentStep = currentCheckboxStep(for: todo) else {
            completeTodo(todo)
            return
        }

        currentStep.checked = true
        if todo.status == .open {
            todo.status = .inProgress
        }
        todo.updatedAt = Date()

        do {
            try modelContext.save()
            todoMessage = "Checklist item completed."
            Task { @MainActor in
                _ = await LisdoActiveTaskActivityController.startOrUpdate(todo: todo, categoryName: category.name)
            }
        } catch {
            todoMessage = "Could not update checklist item: \(error.localizedDescription)"
        }
    }

    private func endFocus(_ todo: Todo) {
        todo.status = .open
        todo.updatedAt = Date()

        do {
            try modelContext.save()
            todoMessage = "Focus ended."
            Task { @MainActor in
                _ = await LisdoActiveTaskActivityController.end(todo: todo, categoryName: category.name)
                await LisdoPomodoroActivityController.end(todoID: todo.id)
            }
        } catch {
            todoMessage = "Could not end focus: \(error.localizedDescription)"
        }
    }

    private func completeTodo(_ todo: Todo) {
        todo.status = .completed
        todo.updatedAt = Date()
        todo.blocks?.forEach { block in
            block.checked = true
        }

        do {
            try modelContext.save()
            todoMessage = "Completed todo."
            Task { @MainActor in
                _ = await LisdoActiveTaskActivityController.end(todo: todo, categoryName: category.name)
                await LisdoPomodoroActivityController.end(todoID: todo.id)
            }
        } catch {
            todoMessage = "Could not complete todo: \(error.localizedDescription)"
        }
    }

    private func deleteTodo(_ todo: Todo) {
        modelContext.delete(todo)

        do {
            try modelContext.save()
            todoMessage = "Deleted todo."
        } catch {
            todoMessage = "Could not delete todo: \(error.localizedDescription)"
        }
    }

    private func currentCheckboxStep(for todo: Todo) -> TodoBlock? {
        (todo.blocks ?? [])
            .sortedForCategoryFocus()
            .first { !$0.checked }
    }
}

private extension Array where Element == TodoBlock {
    func sortedForCategoryFocus() -> [TodoBlock] {
        filter { $0.type == .checkbox }
            .sorted { lhs, rhs in
                if lhs.order != rhs.order {
                    return lhs.order < rhs.order
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }
}
