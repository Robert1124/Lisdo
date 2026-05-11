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
    var openDraft: (ProcessingDraft) -> Void = { _ in }
    var openPomodoro: (Todo) -> Void = { _ in }

    @State private var editingCategory: CategoryEditorState?
    @State private var categoryMessage: String?
    @State private var pendingDeleteConfirmation: CategoryDeleteConfirmation?

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
                                todos: activeTodosForCategory(category.id),
                                openPomodoro: openPomodoro
                            )
                        } label: {
                            CategoryTile(category: category, count: activeTodosForCategory(category.id).count)
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
                        ForEach(Array(LisdoCategorySmartListKind.defaultKinds.enumerated()), id: \.element) { index, kind in
                            NavigationLink {
                                CategorySmartListDetailView(
                                    kind: kind,
                                    todos: todos,
                                    drafts: drafts,
                                    captures: captures,
                                    categories: categories,
                                    openDraft: openDraft,
                                    openPomodoro: openPomodoro
                                )
                            } label: {
                                SmartListRow(
                                    icon: kind.systemImage,
                                    title: kind.title,
                                    detail: smartListDetail(for: kind),
                                    showDivider: index < LisdoCategorySmartListKind.defaultKinds.count - 1
                                )
                            }
                            .buttonStyle(.plain)
                        }
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
        .confirmationDialog(
            "Delete category?",
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible,
            presenting: pendingDeleteConfirmation
        ) { confirmation in
            Button("Delete category", role: .destructive) {
                confirmDeleteCategory(confirmation.category)
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteConfirmation = nil
            }
        } message: { confirmation in
            Text(confirmation.message)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
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
        activeTodos.filter {
            Calendar.current.isDateInToday($0.dueDate ?? .distantPast)
            || Calendar.current.isDateInToday($0.scheduledDate ?? .distantPast)
            || ($0.dueDateText?.localizedCaseInsensitiveContains("today") == true)
        }.count
    }

    private var failedCount: Int {
        captures.filter { $0.status == .failed }.count
    }

    private var archivedCount: Int {
        todos.filter { $0.status == .completed || $0.status == .archived }.count
    }

    private var trashedCount: Int {
        todos.filter { $0.status == .trashed }.count
    }

    private var activeTodos: [Todo] {
        todos.filter { $0.status == .open || $0.status == .inProgress }
    }

    private func activeTodosForCategory(_ id: String) -> [Todo] {
        activeTodos.filter { $0.categoryId == id }
    }

    private func smartListDetail(for kind: LisdoCategorySmartListKind) -> String {
        switch kind {
        case .today:
            "\(todayCount) due"
        case .drafts:
            "\(drafts.count) ready"
        case .archive:
            "\(archivedCount) completed"
        case .trash:
            "\(trashedCount) deleted"
        case .attention:
            "\(failedCount) failed"
        }
    }

    private func canDelete(_ category: Category) -> Bool {
        !isInboxCategory(category)
    }

    private func deleteCategory(_ category: Category) {
        guard canDelete(category) else {
            categoryMessage = "Inbox is the fallback category and cannot be deleted."
            return
        }

        let references = referenceCounts(for: category)
        guard references.total > 0 else {
            confirmDeleteCategory(category)
            return
        }

        pendingDeleteConfirmation = CategoryDeleteConfirmation(
            category: category,
            todoCount: references.todos,
            draftCount: references.drafts
        )
    }

    private func confirmDeleteCategory(_ category: Category) {
        let fallbackCategoryId = inboxCategoryId
        let movedTodoCount = todos.filter { $0.categoryId == category.id }.count
        let movedDraftCount = drafts.filter { $0.recommendedCategoryId == category.id }.count

        for todo in todos where todo.categoryId == category.id {
            todo.categoryId = fallbackCategoryId
            todo.updatedAt = Date()
        }

        for draft in drafts where draft.recommendedCategoryId == category.id {
            draft.recommendedCategoryId = fallbackCategoryId
        }

        modelContext.delete(category)
        do {
            try modelContext.save()
            pendingDeleteConfirmation = nil
            if movedTodoCount > 0 || movedDraftCount > 0 {
                categoryMessage = "\(category.name) was deleted. \(movedTodoCount) todo\(movedTodoCount == 1 ? "" : "s") and \(movedDraftCount) draft recommendation\(movedDraftCount == 1 ? "" : "s") moved to Inbox."
            } else {
                categoryMessage = "\(category.name) was deleted."
            }
        } catch {
            categoryMessage = "Could not delete \(category.name). Try again after sync finishes."
        }
    }

    private func isInboxCategory(_ category: Category) -> Bool {
        category.id == DefaultCategorySeeder.inboxCategoryId
            || category.name.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare("Inbox") == .orderedSame
    }

    private var inboxCategoryId: String {
        categories.first(where: isInboxCategory)?.id ?? DefaultCategorySeeder.inboxCategoryId
    }

    private func referenceCounts(for category: Category) -> (todos: Int, drafts: Int, total: Int) {
        let todoCount = todos.filter { $0.categoryId == category.id }.count
        let draftCount = drafts.filter { $0.recommendedCategoryId == category.id }.count
        return (todoCount, draftCount, todoCount + draftCount)
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteConfirmation = nil
                }
            }
        )
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

private struct CategoryDeleteConfirmation: Identifiable {
    let id = UUID()
    var category: Category
    var todoCount: Int
    var draftCount: Int

    var message: String {
        "\(category.name) is used by \(todoCount) todo\(todoCount == 1 ? "" : "s") and \(draftCount) draft recommendation\(draftCount == 1 ? "" : "s"). Deleting it will move those items to Inbox. No todos or drafts will be deleted."
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
                            Text("Inbox is Lisdo's fallback category and cannot be deleted.")
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

private struct CategorySmartListDetailView: View {
    @Environment(\.modelContext) private var modelContext

    var kind: LisdoCategorySmartListKind
    var todos: [Todo]
    var drafts: [ProcessingDraft]
    var captures: [CaptureItem]
    var categories: [Category]
    var openDraft: (ProcessingDraft) -> Void
    var openPomodoro: (Todo) -> Void

    @State private var selectedTodoDetail: CategoryTodoDetailSelection?
    @State private var message: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if let message {
                    ProductStateRow(icon: "checkmark.circle", title: "\(kind.title) update", message: message)
                }

                content
            }
            .padding(16)
        }
        .background(LisdoTheme.surface)
        .navigationTitle(kind.title)
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
                CategoryMissingTodoDetailView()
                    .presentationDetents([.medium])
                    .presentationBackground(LisdoTheme.surface)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .today, .archive, .trash:
            todoList
        case .drafts:
            draftList
        case .attention:
            attentionList
        }
    }

    @ViewBuilder
    private var todoList: some View {
        let rows = todosForKind

        if rows.isEmpty {
            ProductStateRow(icon: kind.systemImage, title: emptyTitle, message: emptyMessage)
        } else {
            if kind == .trash {
                ProductStateRow(
                    icon: "trash",
                    title: "30 day retention",
                    message: "Deleted todos stay in Trash for 30 days, then Lisdo removes them permanently."
                )
            }

            ForEach(rows, id: \.id) { todo in
                CompactTodoCardView(
                    todo: todo,
                    categoryName: categoryName(for: todo.categoryId),
                    onOpen: { selectedTodoDetail = CategoryTodoDetailSelection(todoID: todo.id) },
                    onStartFocus: kind == .trash ? nil : { openPomodoro(todo) },
                    onDelete: { deleteAction(for: todo) }
                )
            }
        }
    }

    @ViewBuilder
    private var draftList: some View {
        if drafts.isEmpty {
            ProductStateRow(icon: "sparkle", title: "No AI drafts", message: "Reviewable drafts will appear here before they become saved todos.")
        } else {
            ForEach(drafts, id: \.id) { draft in
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
    }

    @ViewBuilder
    private var attentionList: some View {
        let failed = captures.filter { $0.status == .failed }

        if failed.isEmpty {
            ProductStateRow(icon: "exclamationmark.circle", title: "Nothing needs attention", message: "Failed captures will appear here when processing needs review.")
        } else {
            ForEach(failed, id: \.id) { capture in
                PendingCaptureRow(capture: capture)
            }
        }
    }

    private var todosForKind: [Todo] {
        switch kind {
        case .today:
            return activeTodos.filter {
                Calendar.current.isDateInToday($0.dueDate ?? .distantPast)
                || Calendar.current.isDateInToday($0.scheduledDate ?? .distantPast)
                || ($0.dueDateText?.localizedCaseInsensitiveContains("today") == true)
            }
        case .archive:
            return todos.filter { $0.status == .completed || $0.status == .archived }
        case .trash:
            return todos.filter { $0.status == .trashed }
        case .drafts, .attention:
            return []
        }
    }

    private var activeTodos: [Todo] {
        todos.filter { $0.status == .open || $0.status == .inProgress }
    }

    private var emptyTitle: String {
        switch kind {
        case .today:
            "Nothing due today"
        case .archive:
            "Archive is empty"
        case .trash:
            "Trash is empty"
        case .drafts, .attention:
            kind.title
        }
    }

    private var emptyMessage: String {
        switch kind {
        case .today:
            "Approved active todos due or scheduled today will collect here."
        case .archive:
            "Completed todos you archive will collect here."
        case .trash:
            "Deleted todos will stay here for 30 days before permanent removal."
        case .drafts, .attention:
            ""
        }
    }

    private func categoryName(for id: String?) -> String {
        categories.first(where: { $0.id == id })?.name ?? "General"
    }

    private func deleteAction(for todo: Todo) {
        if kind == .trash {
            modelContext.delete(todo)
            message = "Todo permanently deleted."
        } else {
            TodoTrashPolicy.moveToTrash([todo])
            message = "Todo moved to Trash."
            Task { @MainActor in
                await LisdoReminderNotificationScheduler.syncNotifications(for: todo)
            }
        }

        saveChanges()
    }

    private func deleteDraft(_ draft: ProcessingDraft) {
        let captureIds = CaptureDeletionPolicy.captureIdsToDelete(whenDeleting: draft, captures: captures)
        for capture in captures where captureIds.contains(capture.id) {
            modelContext.delete(capture)
        }
        modelContext.delete(draft)
        message = "Draft deleted."
        saveChanges()
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
            message = "Saved draft as todo."
        } catch {
            message = "Could not save draft: \(error.localizedDescription)"
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

    private func toggleCompletion(_ todo: Todo) {
        CaptureBatchActions.toggleSavedTodoCompletion(todo)
        message = todo.status == .completed ? "Completed todo." : "Reopened todo."
        Task { @MainActor in
            await LisdoReminderNotificationScheduler.syncNotifications(for: todo)
        }
        saveChanges()
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            message = "Could not save changes: \(error.localizedDescription)"
        }
    }
}

private struct CategoryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.name) private var allCategories: [Category]

    var category: Category
    var todos: [Todo]
    var openPomodoro: (Todo) -> Void
    @State private var todoMessage: String?
    @State private var selectedTodoDetail: CategoryTodoDetailSelection?

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
                        CompactTodoCardView(
                            todo: todo,
                            categoryName: category.name,
                            onOpen: { selectedTodoDetail = CategoryTodoDetailSelection(todoID: todo.id) },
                            onStartFocus: { openPomodoro(todo) },
                            onDelete: { deleteTodo(todo) }
                        )
                    }
                }
            }
            .padding(16)
        }
        .background(LisdoTheme.surface)
        .navigationTitle(category.name)
        .sheet(item: $selectedTodoDetail) { selection in
            if let todo = todos.first(where: { $0.id == selection.todoID }) {
                TodoDetailSheet(
                    todo: todo,
                    categories: allCategories,
                    openPomodoro: openPomodoro
                )
                .presentationDetents([.fraction(0.78), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(LisdoTheme.surface)
            } else {
                CategoryMissingTodoDetailView()
                    .presentationDetents([.medium])
                    .presentationBackground(LisdoTheme.surface)
            }
        }
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
        TodoTrashPolicy.moveToTrash([todo])

        do {
            try modelContext.save()
            todoMessage = "Todo moved to Trash."
            Task { @MainActor in
                await LisdoReminderNotificationScheduler.syncNotifications(for: todo)
            }
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

private struct CategoryTodoDetailSelection: Identifiable, Hashable {
    let todoID: UUID
    var id: UUID { todoID }
}

private struct CategoryMissingTodoDetailView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "square.grid.2x2.badge.xmark")
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
