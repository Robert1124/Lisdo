import AppKit
import LisdoCore
import SwiftData
import SwiftUI

struct LisdoMacRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \ProcessingDraft.generatedAt, order: .reverse) private var drafts: [ProcessingDraft]
    @Query(sort: \CaptureItem.createdAt, order: .reverse) private var captures: [CaptureItem]
    @Query(sort: \Todo.updatedAt, order: .reverse) private var todos: [Todo]

    @State private var selection: LisdoMacSelection = .inbox
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchText = ""
    @State private var isSearchExpanded = false
    @State private var captureRequest: LisdoMacCaptureRequest?
    @State private var showsNewCategory = false
    @State private var showsFilterPopover = false
    @State private var searchFilters = LisdoMacSearchFilters()
    @State private var focusedTodoId: UUID?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LisdoMacSidebarView(
                selection: $selection,
                categories: categories,
                drafts: filteredDrafts,
                captures: filteredCaptures,
                todos: filteredTodos,
                onAddCategory: {
                    showsNewCategory = true
                }
            )
        } detail: {
            LisdoMacDetailHost(
                selection: $selection,
                selectionTitle: selectionTitle,
                drafts: filteredDrafts,
                captures: filteredCaptures,
                todos: filteredTodos,
                categories: categories,
                todayTodos: todayTodos,
                fromIPhoneCaptures: fromIPhoneCaptures,
                focusedTodoId: $focusedTodoId
            )
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            LisdoMacToolbarContent(
                searchText: $searchText,
                isSearchExpanded: $isSearchExpanded,
                showsFilterPopover: $showsFilterPopover,
                filters: $searchFilters,
                categories: categories,
                onCapture: {
                    captureRequest = LisdoMacCaptureRequest(initialAction: .text)
                }
            )
        }
        .onAppear(perform: bootstrapDefaultCategories)
        .onChange(of: categorySyncSignature) { _, _ in
            bootstrapDefaultCategories()
        }
        .onChange(of: showsFilterPopover) { _, isShowing in
            if !isShowing {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: LisdoMacNotifications.openCapture)) { _ in
            captureRequest = LisdoMacCaptureRequest(initialAction: .text)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: LisdoMacNotifications.selectScreenArea)) { _ in
            captureRequest = LisdoMacCaptureRequest(initialAction: .selectedArea)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: LisdoMacNotifications.openFromIPhone)) { _ in
            selection = .fromIPhone
            NSApp.activate(ignoringOtherApps: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: LisdoMacNotifications.openTodo)) { notification in
            guard let todoId = notification.userInfo?[LisdoMacNotifications.todoIdUserInfoKey] as? UUID,
                  let todo = todos.first(where: { $0.id == todoId })
            else {
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            focusedTodoId = todo.id
            switch todo.status {
            case .trashed:
                selection = .trash
            case .archived, .completed:
                selection = .archive
            default:
                selection = .category(todo.categoryId)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        .sheet(item: $captureRequest) { request in
            LisdoCaptureSheet(categories: categories, initialAction: request.initialAction)
                .frame(minWidth: 520, minHeight: 420)
        }
        .sheet(isPresented: $showsNewCategory) {
            LisdoMacCategoryEditorSheet(category: nil)
                .frame(minWidth: 520, minHeight: 520)
        }
    }

    private var selectionTitle: String {
        if case .category(let id) = selection, let category = categories.category(id: id) {
            return category.name
        }
        return selection.title
    }

    private var filteredDrafts: [ProcessingDraft] {
        advancedSearchResult.drafts
    }

    private var filteredCaptures: [CaptureItem] {
        advancedSearchResult.captures
    }

    private var filteredTodos: [Todo] {
        advancedSearchResult.todos
    }

    private var advancedSearchResult: AdvancedSearchResult {
        LisdoAdvancedSearch.filter(
            captures: captures,
            drafts: drafts,
            todos: todos,
            query: AdvancedSearchQuery(
                text: searchText.lisdoTrimmed.isEmpty ? nil : searchText.lisdoTrimmed,
                captureStatuses: searchFilters.captureStatus.map { [$0] } ?? [],
                providerModes: [],
                categoryIds: searchFilters.categoryId.map { [$0] } ?? [],
                todoStatuses: searchFilters.todoStatus.map { [$0] } ?? [],
                priorities: searchFilters.priority.map { [$0] } ?? []
            )
        )
    }

    private var todayTodos: [Todo] {
        let calendar = Calendar.current
        return filteredTodos.filter { todo in
            guard todo.status == .open || todo.status == .inProgress else {
                return false
            }
            if let dueDate = todo.dueDate, calendar.isDateInToday(dueDate) {
                return true
            }
            if let scheduledDate = todo.scheduledDate, calendar.isDateInToday(scheduledDate) {
                return true
            }
            return todo.dueDateText?.localizedCaseInsensitiveContains("today") == true
        }
    }

    private var activeTodos: [Todo] {
        filteredTodos.filter { $0.status == .open || $0.status == .inProgress }
    }

    private var fromIPhoneCaptures: [CaptureItem] {
        LisdoMacMVP2Processing.pendingQueue(from: filteredCaptures)
    }

    private var categorySyncSignature: String {
        categories
            .map { "\($0.id)|\($0.name)" }
            .joined(separator: "\u{001F}")
    }

    private func bootstrapDefaultCategories() {
        _ = try? DefaultCategorySeeder.seedDefaults(in: modelContext)
    }
}

private struct LisdoMacDetailHost: View {
    @Binding var selection: LisdoMacSelection
    let selectionTitle: String
    let drafts: [ProcessingDraft]
    let captures: [CaptureItem]
    let todos: [Todo]
    let categories: [Category]
    let todayTodos: [Todo]
    let fromIPhoneCaptures: [CaptureItem]
    @Binding var focusedTodoId: UUID?

    var body: some View {
        detailView
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(LisdoMacTheme.surface)
            .navigationTitle(selectionTitle)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .inbox:
            LisdoInboxTriageView(
                title: "Inbox",
                subtitle: "Review drafts, pending captures, and saved todos.",
                drafts: drafts,
                captures: captures,
                todos: todos,
                categories: categories
            )
        case .drafts:
            LisdoInboxTriageView(
                title: "Drafts",
                subtitle: "AI output stays here until you approve it.",
                drafts: drafts,
                captures: [],
                todos: [],
                categories: categories
            )
        case .today:
            LisdoTodayView(todos: todayTodos, categories: categories)
        case .plan:
            LisdoPlanView(
                todos: todos,
                categories: categories,
                onOpenTodo: { todo in
                    focusedTodoId = todo.id
                    selection = .category(todo.categoryId)
                }
            )
        case .fromIPhone:
            LisdoFromIPhoneView(captures: fromIPhoneCaptures, categories: categories)
        case .archive:
            LisdoMacTodoCollectionView(
                title: "Archive",
                subtitle: "Completed and archived Lisdo todos.",
                emptySystemImage: "archivebox",
                emptyTitle: "Archive is empty",
                emptyMessage: "Completed todos can be archived here when they no longer need active attention.",
                todos: archiveTodos,
                categories: categories,
                focusedTodoId: focusedTodoId,
                allowsCompletionToggle: true,
                allowsDelete: true
            )
        case .trash:
            LisdoMacTodoCollectionView(
                title: "Trash",
                subtitle: "Deleted todos stay here for 30 days before cleanup.",
                emptySystemImage: "trash",
                emptyTitle: "Trash is empty",
                emptyMessage: "Deleted todos will collect here temporarily.",
                todos: trashTodos,
                categories: categories,
                focusedTodoId: focusedTodoId,
                allowsCompletionToggle: false,
                allowsDelete: false
            )
        case .category(let categoryId):
            LisdoCategoryDetailView(
                category: categories.category(id: categoryId),
                todos: todos.filter { ($0.status == .open || $0.status == .inProgress) && $0.categoryId == categoryId },
                drafts: drafts.filter { $0.recommendedCategoryId == categoryId },
                categories: categories,
                focusedTodoId: focusedTodoId
            )
        }
    }

    private var archiveTodos: [Todo] {
        todos.filter { $0.status == .completed || $0.status == .archived }
    }

    private var trashTodos: [Todo] {
        todos.filter { $0.status == .trashed }
    }
}

private struct LisdoMacToolbarContent: ToolbarContent {
    @Binding var searchText: String
    @Binding var isSearchExpanded: Bool
    @Binding var showsFilterPopover: Bool
    @Binding var filters: LisdoMacSearchFilters

    let categories: [Category]
    let onCapture: () -> Void

    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            toolbarItems
                .sharedBackgroundVisibility(.hidden)
        } else {
            toolbarItems
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 2) {
                LisdoMacToolbarItemHost {
                    LisdoMacSearchToolbarControl(
                        text: $searchText,
                        isExpanded: $isSearchExpanded
                    )
                }

                LisdoMacToolbarItemHost {
                    filterButton
                }

                LisdoMacToolbarItemHost {
                    quickCaptureButton
                }

                LisdoMacToolbarItemHost {
                    settingsButton
                }
            }
        }
    }

    private var filterButton: some View {
        Button {
            showsFilterPopover.toggle()
        } label: {
            LisdoMacToolbarCircleLabel(
                systemImage: filters.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .popover(isPresented: $showsFilterPopover, arrowEdge: .bottom) {
            LisdoMacFilterPopover(
                filters: $filters,
                categories: categories,
                onDismissFocus: {
                    showsFilterPopover = false
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
            )
        }
        .help(filters.hasActiveFilters ? "Filter active" : "Filter")
        .accessibilityLabel(filters.hasActiveFilters ? "Filters Active" : "Filters")
    }

    private var quickCaptureButton: some View {
        Button(action: onCapture) {
            LisdoMacToolbarCircleLabel(
                systemImage: "plus",
                foreground: LisdoMacTheme.onAccent,
                background: LisdoMacTheme.ink2
            )
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: [.command])
        .focusable(false)
        .focusEffectDisabled()
        .help("Quick capture")
        .accessibilityLabel("Quick Capture")
    }

    private var settingsButton: some View {
        SettingsLink {
            LisdoMacToolbarCircleLabel(systemImage: "gearshape")
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .help("Settings")
        .accessibilityLabel("Settings")
    }
}

private struct LisdoMacSearchToolbarControl: View {
    @Binding var text: String
    @Binding var isExpanded: Bool
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        Group {
            if isExpanded {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(LisdoMacTheme.ink3)

                    TextField("Search captures, drafts, todos", text: $text)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .tint(LisdoMacTheme.ink2)
                        .frame(width: 230)

                    Button {
                        text = ""
                        isSearchFocused = false
                        isExpanded = false
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(LisdoMacTheme.ink4)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .focusEffectDisabled()
                    .help("Close search")
                    .accessibilityLabel("Close Search")
                }
                .padding(.leading, 12)
                .padding(.trailing, 10)
                .frame(height: 38)
                .background(LisdoMacTheme.surface2, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(LisdoMacTheme.divider.opacity(0.82))
                }
                .onAppear {
                    isSearchFocused = true
                }
            } else {
                Button {
                    isExpanded = true
                } label: {
                    LisdoMacToolbarCircleLabel(systemImage: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
                .help("Search")
                .accessibilityLabel("Search")
            }
        }
        .onChange(of: isSearchFocused) { _, isFocused in
            if !isFocused && text.lisdoTrimmed.isEmpty {
                isExpanded = false
            }
        }
    }
}

private struct LisdoMacToolbarItemHost<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 2)
            .frame(minWidth: 44, minHeight: 42)
    }
}

private struct LisdoMacToolbarCircleLabel: View {
    let systemImage: String
    var foreground: Color = LisdoMacTheme.ink2
    var background: Color = LisdoMacTheme.surface2

    var body: some View {
        Image(systemName: systemImage)
            .font(.callout.weight(.semibold))
            .foregroundStyle(foreground)
            .frame(width: 40, height: 40)
            .background(background, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(LisdoMacTheme.divider.opacity(0.78))
            }
            .contentShape(Circle())
            .accessibilityHidden(true)
    }
}

private struct LisdoMacSearchFilters: Equatable {
    var captureStatus: CaptureStatus?
    var categoryId: String?
    var todoStatus: TodoStatus?
    var priority: TodoPriority?

    var hasActiveFilters: Bool {
        captureStatus != nil
            || categoryId != nil
            || todoStatus != nil
            || priority != nil
    }

    mutating func clear() {
        captureStatus = nil
        categoryId = nil
        todoStatus = nil
        priority = nil
    }
}

private struct LisdoMacFilterPopover: View {
    @Binding var filters: LisdoMacSearchFilters
    let categories: [Category]
    let onDismissFocus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Filters")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    filters.clear()
                    onDismissFocus()
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
                .disabled(!filters.hasActiveFilters)
            }

            filterMenu(
                title: "Capture",
                selection: $filters.captureStatus,
                values: CaptureStatus.allCases,
                label: { readableEnumLabel($0.rawValue) }
            )

            filterMenu(
                title: "Category",
                selection: $filters.categoryId,
                values: categories.map(\.id),
                label: { categoryName(for: $0) }
            )

            filterMenu(
                title: "Todo",
                selection: $filters.todoStatus,
                values: TodoStatus.allCases,
                label: { readableEnumLabel($0.rawValue) }
            )

            filterMenu(
                title: "Priority",
                selection: $filters.priority,
                values: TodoPriority.allCases,
                label: { readableEnumLabel($0.rawValue) }
            )

            Text("Filters apply immediately together with the search text.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 310)
        .focusable(false)
        .focusEffectDisabled()
    }

    @ViewBuilder
    private func filterMenu<Value: Hashable>(
        title: String,
        selection: Binding<Value?>,
        values: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            Menu {
                Button("Any") {
                    selection.wrappedValue = nil
                    onDismissFocus()
                }
                Divider()
                ForEach(values, id: \.self) { value in
                    Button(label(value)) {
                        selection.wrappedValue = value
                        onDismissFocus()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selection.wrappedValue.map(label) ?? "Any")
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .lisdoGlassSurface(
                    cornerRadius: 15,
                    tint: selection.wrappedValue == nil ? nil : LisdoMacTheme.info.opacity(0.14),
                    interactive: true
                )
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()
        }
    }

    private func categoryName(for id: String) -> String {
        categories.first(where: { $0.id == id })?.name ?? "Unknown"
    }

    private func readableEnumLabel(_ rawValue: String) -> String {
        rawValue.unicodeScalars.reduce(into: "") { result, scalar in
            let character = Character(scalar)
            if CharacterSet.uppercaseLetters.contains(scalar), !result.isEmpty {
                result.append(" ")
            }
            result.append(character)
        }
        .capitalized
    }
}
