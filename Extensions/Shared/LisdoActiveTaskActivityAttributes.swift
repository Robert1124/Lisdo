import ActivityKit
import Foundation
import LisdoCore

struct LisdoActiveTaskActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var currentStep: String
        var nextStep: String?
        var progress: Double
        var progressLabel: String
        var completedStepCount: Int
        var totalStepCount: Int

        init(
            currentStep: String,
            nextStep: String? = nil,
            progress: Double,
            progressLabel: String,
            completedStepCount: Int,
            totalStepCount: Int
        ) {
            self.currentStep = currentStep
            self.nextStep = nextStep
            self.progress = min(max(progress, 0), 1)
            self.progressLabel = progressLabel
            self.completedStepCount = max(completedStepCount, 0)
            self.totalStepCount = max(totalStepCount, 0)
        }

        init(snapshot: ActiveTaskSnapshot) {
            let totalStepCount = snapshot.totalStepCount
            let progress = totalStepCount > 0
                ? Double(snapshot.completedStepCount) / Double(totalStepCount)
                : 0

            self.init(
                currentStep: snapshot.currentStep?.content ?? (snapshot.isComplete ? "All steps complete" : "No steps added"),
                nextStep: snapshot.nextStep?.content,
                progress: progress,
                progressLabel: snapshot.progressLabel,
                completedStepCount: snapshot.completedStepCount,
                totalStepCount: totalStepCount
            )
        }
    }

    var todoId: String
    var activeTaskTitle: String
    var category: String

    init(snapshot: ActiveTaskSnapshot, category: String) {
        self.todoId = snapshot.todoId.uuidString
        self.activeTaskTitle = snapshot.title
        self.category = category
    }
}
