import ActivityKit
import Foundation

struct LisdoPomodoroActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String
        var endDate: Date?
        var remainingSeconds: Double
        var totalSeconds: Double
        var isRunning: Bool
        var completedFocusCount: Int

        init(
            phase: String,
            endDate: Date?,
            remainingSeconds: Double,
            totalSeconds: Double,
            isRunning: Bool,
            completedFocusCount: Int
        ) {
            self.phase = phase
            self.endDate = endDate
            self.remainingSeconds = max(remainingSeconds, 0)
            self.totalSeconds = max(totalSeconds, 1)
            self.isRunning = isRunning
            self.completedFocusCount = max(completedFocusCount, 0)
        }
    }

    var todoId: String
    var title: String
    var categoryName: String
}
