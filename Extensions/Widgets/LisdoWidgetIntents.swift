import ActivityKit
import AppIntents
import Foundation
import LisdoCore
import WidgetKit

// Widget intents are intentionally Todo-only. Captures and provider drafts must stay in the app review flow.
struct StartTodoIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Todo"
    static var description = IntentDescription("Marks an existing Lisdo todo as the active task.")

    @Parameter(title: "Todo ID")
    var todoID: String

    init() {
        todoID = ""
    }

    init(todoID: String) {
        self.todoID = todoID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await LisdoWidgetDataStore.startTodo(idString: todoID)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct ToggleTodoBlockIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Todo Step"
    static var description = IntentDescription("Toggles an existing step on an approved Lisdo todo.")

    @Parameter(title: "Todo ID")
    var todoID: String

    @Parameter(title: "Block ID")
    var blockID: String

    init() {
        todoID = ""
        blockID = ""
    }

    init(todoID: String, blockID: String) {
        self.todoID = todoID
        self.blockID = blockID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await LisdoWidgetDataStore.toggleBlock(todoIDString: todoID, blockIDString: blockID)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct CompleteTodoIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Todo"
    static var description = IntentDescription("Completes an existing approved Lisdo todo.")

    @Parameter(title: "Todo ID")
    var todoID: String

    init() {
        todoID = ""
    }

    init(todoID: String) {
        self.todoID = todoID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await LisdoWidgetDataStore.completeTodo(idString: todoID)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

@MainActor
enum LisdoWidgetLiveActivityUpdater {
    static func updateExistingActivity(for todo: Todo, categoryName: String) async {
        _ = categoryName

        guard let snapshot = DailyExperienceState.liveActivitySnapshot(from: [todo]) else {
            return
        }

        let content = ActivityContent(
            state: LisdoActiveTaskActivityAttributes.ContentState(snapshot: snapshot),
            staleDate: Date().addingTimeInterval(60 * 60)
        )

        for activity in Activity<LisdoActiveTaskActivityAttributes>.activities
            where activity.attributes.todoId == todo.id.uuidString {
            await activity.update(content)
        }
    }

    static func endExistingActivity(for todo: Todo, categoryName: String) async {
        let snapshot = DailyExperienceState.liveActivitySnapshot(from: [todo])
        let finalContent = snapshot.map {
            ActivityContent(
                state: LisdoActiveTaskActivityAttributes.ContentState(snapshot: $0),
                staleDate: nil
            )
        }

        for activity in Activity<LisdoActiveTaskActivityAttributes>.activities
            where activity.attributes.todoId == todo.id.uuidString {
            await activity.end(finalContent, dismissalPolicy: .immediate)
        }

        _ = categoryName
    }
}
