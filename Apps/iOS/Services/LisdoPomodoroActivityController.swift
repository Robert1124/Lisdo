import ActivityKit
import Foundation
import LisdoCore

@MainActor
enum LisdoPomodoroActivityController {
    static var disabledStatusText: String? {
        ActivityAuthorizationInfo().areActivitiesEnabled
            ? nil
            : "Live Activity is disabled in Settings. The Pomodoro timer still runs in Lisdo."
    }

    static func startOrUpdate(
        todo: Todo,
        categoryName: String,
        phase: String,
        endDate: Date?,
        remainingSeconds: TimeInterval,
        totalSeconds: TimeInterval,
        isRunning: Bool,
        completedFocusCount: Int
    ) async -> String {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return "Pomodoro is running in Lisdo. Live Activity is disabled in Settings."
        }

        let attributes = LisdoPomodoroActivityAttributes(
            todoId: todo.id.uuidString,
            title: todo.title,
            categoryName: categoryName
        )
        let content = ActivityContent(
            state: LisdoPomodoroActivityAttributes.ContentState(
                phase: phase,
                endDate: endDate,
                remainingSeconds: remainingSeconds,
                totalSeconds: totalSeconds,
                isRunning: isRunning,
                completedFocusCount: completedFocusCount
            ),
            staleDate: endDate?.addingTimeInterval(60)
        )

        do {
            for activity in Activity<LisdoPomodoroActivityAttributes>.activities
                where activity.attributes.todoId != attributes.todoId {
                await activity.end(nil, dismissalPolicy: .immediate)
            }

            if let existing = Activity<LisdoPomodoroActivityAttributes>.activities.first(where: {
                $0.attributes.todoId == attributes.todoId
            }) {
                await existing.update(content)
                return "Pomodoro Live Activity updated."
            }

            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
            return "Pomodoro Live Activity started."
        } catch {
            return "Pomodoro is running, but Live Activity could not be updated."
        }
    }

    static func end(todoID: UUID) async {
        for activity in Activity<LisdoPomodoroActivityAttributes>.activities
            where activity.attributes.todoId == todoID.uuidString {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
