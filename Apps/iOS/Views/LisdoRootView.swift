import LisdoCore
import SwiftData
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

struct LisdoRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProcessingDraft.generatedAt, order: .reverse) private var drafts: [ProcessingDraft]
    @Query(sort: \CaptureItem.createdAt, order: .reverse) private var captures: [CaptureItem]
    @Query(sort: \Todo.createdAt, order: .reverse) private var todos: [Todo]
    @Query(sort: \Category.name) private var categories: [Category]

    @State private var selectedTab = LisdoTab.inbox
    @State private var activeSheet: LisdoSheet?
    @State private var activePomodoro: PomodoroSelection?
    @State private var pomodoroLaunchError: PomodoroLaunchError?

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                InboxView(
                    drafts: drafts,
                    captures: captures,
                    todos: todos,
                    categories: categories,
                    openDraft: { activeSheet = .draft($0.id) },
                    openPomodoro: startPomodoro
                )
            }
            .tabItem { Label("Inbox", systemImage: "tray") }
            .tag(LisdoTab.inbox)

            NavigationStack {
                CategoriesView(
                    categories: categories,
                    todos: todos,
                    drafts: drafts,
                    captures: captures,
                    openDraft: { activeSheet = .draft($0.id) },
                    openPomodoro: startPomodoro
                )
            }
            .tabItem { Label("Categories", systemImage: "square.grid.2x2") }
            .tag(LisdoTab.categories)

            Color.clear
                .tabItem { Label("Capture", systemImage: "plus.circle.fill") }
                .tag(LisdoTab.capture)

            NavigationStack {
                PlanView(todos: todos, openPomodoro: startPomodoro)
            }
            .tabItem { Label("Plan", systemImage: "calendar") }
            .tag(LisdoTab.plan)

            NavigationStack {
                YouSettingsView()
            }
            .tabItem { Label("You", systemImage: "person.crop.circle") }
            .tag(LisdoTab.you)
        }
        .tint(LisdoTheme.ink1)
        .background(LisdoTheme.surface)
        .onAppear {
            seedDefaultCategoriesIfNeeded()
            purgeExpiredTrashedTodos()
        }
        .onChange(of: categorySyncSignature) { _, _ in
            seedDefaultCategoriesIfNeeded()
        }
        .onChange(of: selectedTab) { _, nextTab in
            if nextTab == .capture {
                activeSheet = .capture
                selectedTab = .inbox
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .capture:
                QuickCaptureSheet(categories: categories)
            case .draft(let draftId):
                if let draft = drafts.first(where: { $0.id == draftId }) {
                    DraftReviewView(
                        draft: draft,
                        categories: categories,
                        sourceText: sourceText(for: draft),
                        onSaved: { activeSheet = nil }
                    )
                } else {
                    MissingDraftView()
                }
            }
        }
        .fullScreenCover(item: $activePomodoro) { selection in
            if let todo = todos.first(where: { $0.id == selection.todoID }) {
                PomodoroFocusView(
                    todo: todo,
                    categoryName: categoryName(for: todo.categoryId),
                    onClose: { activePomodoro = nil },
                    onCompleteTodo: { completePomodoroTodo(todo) }
                )
            } else {
                MissingPomodoroTodoView {
                    activePomodoro = nil
                }
            }
        }
        .alert(item: $pomodoroLaunchError) { error in
            Alert(
                title: Text("Could not start Pomodoro"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func sourceText(for draft: ProcessingDraft) -> String {
        captures.first(where: { $0.id == draft.captureItemId })?.sourceText
        ?? captures.first(where: { $0.id == draft.captureItemId })?.transcriptText
        ?? "Source capture is no longer available on this device."
    }

    private var categorySyncSignature: String {
        categories
            .map { "\($0.id)|\($0.name)" }
            .joined(separator: "\u{001F}")
    }

    private func seedDefaultCategoriesIfNeeded() {
        _ = try? DefaultCategorySeeder.seedDefaults(in: modelContext)
    }

    private func purgeExpiredTrashedTodos() {
        let expired = TodoTrashPolicy.expiredTrashedTodos(todos)
        guard !expired.isEmpty else { return }

        for todo in expired {
            modelContext.delete(todo)
        }
        try? modelContext.save()
    }

    private func startPomodoro(_ todo: Todo) {
        let now = Date()
        for activeTodo in todos where activeTodo.status == .inProgress && activeTodo.id != todo.id {
            activeTodo.status = .open
            activeTodo.updatedAt = now
        }

        todo.status = .inProgress
        todo.updatedAt = now

        do {
            try modelContext.save()
            reloadWidgetTimelines()
            activePomodoro = PomodoroSelection(todoID: todo.id)
        } catch {
            pomodoroLaunchError = PomodoroLaunchError(message: "Lisdo could not save the todo before starting focus mode. Try again after iCloud finishes syncing.")
        }
    }

    private func completePomodoroTodo(_ todo: Todo) {
        todo.status = .completed
        todo.updatedAt = Date()
        todo.blocks?.forEach { block in
            block.checked = true
        }

        do {
            try modelContext.save()
            reloadWidgetTimelines()
            activePomodoro = nil
            Task { @MainActor in
                await LisdoPomodoroActivityController.end(todoID: todo.id)
            }
        } catch {
            pomodoroLaunchError = PomodoroLaunchError(message: "Lisdo could not complete the todo. Try again after iCloud finishes syncing.")
        }
    }

    private func categoryName(for id: String?) -> String {
        categories.first(where: { $0.id == id })?.name ?? "Inbox"
    }

    private func reloadWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

private enum LisdoTab: Hashable {
    case inbox
    case categories
    case capture
    case plan
    case you
}

private enum LisdoSheet: Identifiable, Hashable {
    case capture
    case draft(UUID)

    var id: String {
        switch self {
        case .capture:
            "capture"
        case .draft(let id):
            "draft-\(id.uuidString)"
        }
    }
}

private struct PomodoroSelection: Identifiable, Hashable {
    let todoID: UUID
    var id: UUID { todoID }
}

private struct PomodoroLaunchError: Identifiable {
    let id = UUID()
    var message: String
}

private struct MissingDraftView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "doc.badge.clock")
                    .font(.system(size: 30))
                    .foregroundStyle(LisdoTheme.ink3)
                Text("Draft unavailable")
                    .font(.title3.weight(.semibold))
                Text("This draft may have already been saved or removed on another device.")
                    .font(.callout)
                    .foregroundStyle(LisdoTheme.ink3)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct MissingPomodoroTodoView: View {
    var close: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 32))
                .foregroundStyle(LisdoTheme.ink3)
            Text("Todo unavailable")
                .font(.title3.weight(.semibold))
            Text("This todo may have been deleted or synced away on another device.")
                .font(.callout)
                .foregroundStyle(LisdoTheme.ink3)
                .multilineTextAlignment(.center)
            Button("Close", action: close)
                .buttonStyle(.borderedProminent)
                .tint(LisdoTheme.ink1)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LisdoTheme.surface)
    }
}
