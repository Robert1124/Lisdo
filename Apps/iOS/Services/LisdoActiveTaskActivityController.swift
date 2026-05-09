import ActivityKit
import Foundation
import LisdoCore

@MainActor
enum LisdoActiveTaskActivityController {
    static var disabledStatusText: String? {
        ActivityAuthorizationInfo().areActivitiesEnabled
            ? nil
            : "Live Activity is disabled in Settings. Task controls still update Lisdo and iCloud."
    }

    static func startOrUpdate(todo: Todo, categoryName: String) async -> String {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return "Active task saved. Live Activity is disabled in Settings."
        }

        guard let snapshot = DailyExperienceState.liveActivitySnapshot(from: [todo]) else {
            return "Active task saved. Start a todo to show it as a Live Activity."
        }

        let attributes = LisdoActiveTaskActivityAttributes(snapshot: snapshot, category: categoryName)
        let content = ActivityContent(
            state: LisdoActiveTaskActivityAttributes.ContentState(snapshot: snapshot),
            staleDate: Date().addingTimeInterval(60 * 60)
        )

        do {
            for activity in Activity<LisdoActiveTaskActivityAttributes>.activities
                where activity.attributes.todoId != attributes.todoId {
                await activity.end(nil, dismissalPolicy: .immediate)
            }

            if let existing = Activity<LisdoActiveTaskActivityAttributes>.activities.first(where: {
                $0.attributes.todoId == attributes.todoId
            }) {
                await existing.update(content)
                return "Live Activity updated for the active task."
            }

            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
            return "Live Activity started for the active task."
        } catch {
            return "Task state was saved, but Live Activity could not be updated."
        }
    }

    static func end(todo: Todo, categoryName: String) async -> String {
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

        return "Live Activity ended. The todo remains saved in Lisdo."
    }

    static func endAll() async {
        for activity in Activity<LisdoActiveTaskActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
