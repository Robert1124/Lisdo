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
    @State private var isApplyingDeferredColumnVisibility = false
    @State private var showsCapture = false
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
                    showsCapture = true
                }
            )
        }
        .onChange(of: columnVisibility) { previousVisibility, requestedVisibility in
            deferColumnVisibilityChangeIfSearching(
                from: previousVisibility,
                to: requestedVisibility
            )
        }
        .onAppear(perform: bootstrapDefaultCategories)
        .onReceive(NotificationCenter.default.publisher(for: LisdoMacNotifications.openCapture)) { _ in
            showsCapture = true
            NSApp.activate(ignoringOtherApps: true)
        }
        .sheet(isPresented: $showsCapture) {
            LisdoCaptureSheet(categories: categories)
                .frame(minWidth: 560, minHeight: 520)
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
                providerModes: searchFilters.providerMode.map { [$0] } ?? [],
                categoryIds: searchFilters.categoryId.map { [$0] } ?? [],
                todoStatuses: searchFilters.todoStatus.map { [$0] } ?? [],
                priorities: searchFilters.priority.map { [$0] } ?? []
            )
        )
    }

    private func deferColumnVisibilityChangeIfSearching(
        from previousVisibility: NavigationSplitViewVisibility,
        to requestedVisibility: NavigationSplitViewVisibility
    ) {
        guard isSearchExpanded, !isApplyingDeferredColumnVisibility else { return }

        isApplyingDeferredColumnVisibility = true
        columnVisibility = previousVisibility

        withAnimation(.snappy(duration: 0.18)) {
            isSearchExpanded = false
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            withAnimation(.snappy(duration: 0.22)) {
                columnVisibility = requestedVisibility
            }
            isApplyingDeferredColumnVisibility = false
        }
    }

    private var todayTodos: [Todo] {
        let calendar = Calendar.current
        return filteredTodos.filter { todo in
            if let dueDate = todo.dueDate, calendar.isDateInToday(dueDate) {
                return true
            }
            if let scheduledDate = todo.scheduledDate, calendar.isDateInToday(scheduledDate) {
                return true
            }
            return todo.dueDateText?.localizedCaseInsensitiveContains("today") == true
        }
    }

    private var fromIPhoneCaptures: [CaptureItem] {
        filteredCaptures.filter { capture in
            capture.createdDevice == .iPhone
            || capture.preferredProviderMode == .macOnlyCLI
            || capture.status == .pendingProcessing
            || capture.status == .processing
            || capture.status == .retryPending
        }
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
                subtitle: "Review drafts, pending captures, and today's saved todos.",
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
        case .category(let categoryId):
            LisdoCategoryDetailView(
                category: categories.category(id: categoryId),
                todos: todos.inCategory(categoryId),
                drafts: drafts.filter { $0.recommendedCategoryId == categoryId },
                categories: categories,
                focusedTodoId: focusedTodoId
            )
        }
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
        ToolbarItemGroup(placement: .primaryAction) {
            LisdoToolbarSearchControl(
                searchText: $searchText,
                isExpanded: $isSearchExpanded
            )

            Button {
                showsFilterPopover.toggle()
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.body.weight(.semibold))
                    .overlay(alignment: .topTrailing) {
                        if filters.hasActiveFilters {
                            Circle()
                                .fill(LisdoMacTheme.info)
                                .frame(width: 6, height: 6)
                                .padding(1)
                        }
                    }
            }
            .popover(isPresented: $showsFilterPopover, arrowEdge: .bottom) {
                LisdoMacFilterPopover(
                    filters: $filters,
                    categories: categories
                )
            }
            .help(filters.hasActiveFilters ? "Filter active" : "Filter")

            Button(action: onCapture) {
                Label("Capture", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .labelStyle(.iconOnly)
            .keyboardShortcut("n", modifiers: [.command])
            .help("Capture")

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .labelStyle(.iconOnly)
            .help("Settings")
        }
    }
}

private struct LisdoMacSearchFilters: Equatable {
    var captureStatus: CaptureStatus?
    var providerMode: ProviderMode?
    var categoryId: String?
    var todoStatus: TodoStatus?
    var priority: TodoPriority?

    var hasActiveFilters: Bool {
        captureStatus != nil
            || providerMode != nil
            || categoryId != nil
            || todoStatus != nil
            || priority != nil
    }

    mutating func clear() {
        captureStatus = nil
        providerMode = nil
        categoryId = nil
        todoStatus = nil
        priority = nil
    }
}

private struct LisdoMacFilterPopover: View {
    @Binding var filters: LisdoMacSearchFilters
    let categories: [Category]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Filters")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    filters.clear()
                }
                .disabled(!filters.hasActiveFilters)
            }

            filterMenu(
                title: "Capture",
                selection: $filters.captureStatus,
                values: CaptureStatus.allCases,
                label: { readableEnumLabel($0.rawValue) }
            )

            filterMenu(
                title: "Provider",
                selection: $filters.providerMode,
                values: DraftProviderFactory.supportedModes,
                label: { DraftProviderFactory.metadata(for: $0).displayName }
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
                }
                Divider()
                ForEach(values, id: \.self) { value in
                    Button(label(value)) {
                        selection.wrappedValue = value
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

private struct LisdoToolbarSearchControl: View {
    @Binding var searchText: String
    @Binding var isExpanded: Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isExpanded {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search captures, drafts, todos", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .frame(width: 260)
                        .onSubmit {
                            isFocused = true
                        }

                    Button {
                        if searchText.isEmpty {
                            closeSearch()
                        } else {
                            searchText = ""
                        }
                    } label: {
                        Image(systemName: searchText.isEmpty ? "xmark" : "xmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(searchText.isEmpty ? "Close Search" : "Clear Search")
                }
                .font(.callout)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .lisdoGlassSurface(cornerRadius: 17, interactive: true)
                .transition(.scale(scale: 0.92, anchor: .trailing).combined(with: .opacity))
                .onAppear {
                    focusSearchField()
                }
                .onChange(of: isExpanded) { _, expanded in
                    if expanded {
                        focusSearchField()
                    } else {
                        isFocused = false
                    }
                }
                .onExitCommand {
                    closeSearch()
                }
            } else {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        isExpanded = true
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(searchText.isEmpty ? LisdoMacTheme.ink1 : LisdoMacTheme.info)
                        .frame(width: 34, height: 34)
                        .contentShape(Circle())
                        .overlay(alignment: .topTrailing) {
                            if !searchText.isEmpty {
                                Circle()
                                    .fill(LisdoMacTheme.info)
                                    .frame(width: 6, height: 6)
                                    .padding(5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .lisdoGlassSurface(
                    cornerRadius: 17,
                    tint: searchText.isEmpty ? nil : LisdoMacTheme.info.opacity(0.14),
                    interactive: true
                )
                .help(searchText.isEmpty ? "Search" : "Search active")
                .accessibilityLabel(searchText.isEmpty ? "Search" : "Search active")
            }
        }
        .animation(.snappy(duration: 0.2), value: isExpanded)
    }

    private func focusSearchField() {
        Task { @MainActor in
            isFocused = true
        }
    }

    private func closeSearch() {
        withAnimation(.snappy(duration: 0.18)) {
            isExpanded = false
        }
    }
}
