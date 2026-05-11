import Foundation
import LisdoCore
import UserNotifications

@MainActor
enum LisdoReminderNotificationScheduler {
    static func syncNotifications(for todo: Todo) async {
        guard todo.status != .completed && todo.status != .archived && todo.status != .trashed else {
            await cancel(reminderIDs: (todo.reminders ?? []).map(\.id))
            return
        }

        for reminder in todo.reminders ?? [] {
            if reminder.isCompleted {
                await cancel(reminderIDs: [reminder.id])
            } else if let reminderDate = reminder.reminderDate, reminderDate > Date() {
                await schedule(reminder: reminder, todo: todo, date: reminderDate)
            } else {
                await cancel(reminderIDs: [reminder.id])
            }
        }
    }

    static func cancel(reminderIDs: [UUID]) async {
        guard !reminderIDs.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: reminderIDs.map(identifier(for:))
        )
    }

    private static func schedule(reminder: TodoReminder, todo: Todo, date: Date) async {
        guard await allowsNotifications() else { return }

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = notificationBody(reminder: reminder, todo: todo)
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(for: reminder.id),
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func allowsNotifications() async -> Bool {
        let settings = await notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) == true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private static func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private static func notificationBody(reminder: TodoReminder, todo: Todo) -> String {
        [todo.title, reminder.reason, reminder.reminderDateText]
            .compactMap { value in
                guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                    return nil
                }
                return trimmed
            }
            .joined(separator: "\n")
    }

    private static func identifier(for reminderID: UUID) -> String {
        "lisdo.todo-reminder.\(reminderID.uuidString)"
    }
}
