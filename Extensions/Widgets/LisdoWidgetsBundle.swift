import ActivityKit
import SwiftUI
import WidgetKit

struct LisdoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> LisdoWidgetEntry {
        .loading()
    }

    func getSnapshot(in context: Context, completion: @escaping (LisdoWidgetEntry) -> Void) {
        if context.isPreview {
            completion(.preview)
        } else {
            completion(LisdoWidgetDataStore.loadEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LisdoWidgetEntry>) -> Void) {
        let entry = LisdoWidgetDataStore.loadEntry()
        let refreshDate = entry.date.addingTimeInterval(LisdoWidgetDataStore.refreshInterval)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}

struct LisdoTodayWidget: Widget {
    let kind = "LisdoTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LisdoWidgetProvider()) { entry in
            LisdoWidgetView(entry: entry)
                .containerBackground(LisdoColor.surface, for: .widget)
        }
        .configurationDisplayName("Lisdo Inbox")
        .description("Review drafts, pending captures, today's tasks, and the active task.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct LisdoWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: LisdoWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallFocusWidget(entry: entry)
        case .systemMedium:
            MediumTodayWidget(entry: entry)
        default:
            LargeTodayWidget(entry: entry)
        }
    }
}

private struct SmallFocusWidget: View {
    let entry: LisdoWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Today's focus")
                .lisdoEyebrow()

            switch entry.state {
            case .loading:
                WidgetStateMessage(title: "Loading Lisdo", message: "Reading synced task state.")
                    .padding(.top, 10)
            case .error:
                WidgetStateMessage(title: "Sync unavailable", message: "Open Lisdo to refresh iCloud state.")
                    .padding(.top, 10)
            case .empty, .content:
                if let focus = entry.closestTodayTodo {
                    Text(focus.title)
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundStyle(LisdoColor.ink)
                        .lineLimit(3)
                        .lineSpacing(2)
                        .padding(.top, 8)

                    Spacer(minLength: 8)

                    TodayTodoMetadata(task: focus, compact: true)
                } else {
                    WidgetStateMessage(title: "Nothing today", message: "No approved todos are due or scheduled today.")
                        .padding(.top, 10)
                    Spacer(minLength: 4)
                    Text("Open Lisdo to capture a task.")
                        .font(.system(size: 10))
                        .foregroundStyle(LisdoColor.secondaryInk)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
    }
}

private struct MediumTodayWidget: View {
    let entry: LisdoWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today")
                    .lisdoEyebrow()
                Spacer()
                Text(entry.todayCountText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(LisdoColor.secondaryInk)
            }

            switch entry.state {
            case .loading:
                WidgetStateMessage(title: "Loading", message: "Reading synced todos.")
            case .error:
                WidgetStateMessage(title: "Sync unavailable", message: "Open Lisdo to refresh widgets.")
            case .empty, .content:
                if entry.todayItems.isEmpty {
                    WidgetStateMessage(title: "Nothing due today", message: "Today's approved todos will appear here.")
                    Spacer(minLength: 0)
                } else {
                    VStack(spacing: 7) {
                        ForEach(entry.todayItems.prefix(4)) { task in
                            TodayTodoRow(task: task)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
    }
}

private struct LargeTodayWidget: View {
    let entry: LisdoWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today · \(entry.shortDateText)")
                    .lisdoEyebrow()
                Spacer()
                Text(entry.todayCountText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(LisdoColor.secondaryInk)
            }

            switch entry.state {
            case .loading:
                WidgetStateMessage(title: "Loading Lisdo", message: "Reading synced task state.")
            case .error(let message):
                WidgetStateMessage(title: "Sync unavailable", message: message)
            case .empty, .content:
                if let focus = entry.closestTodayTodo {
                    TodayFocusBlock(task: focus)

                    VStack(spacing: 8) {
                        ForEach(entry.todayItems.dropFirst().prefix(5)) { task in
                            TodayTodoRow(task: task)
                        }
                    }
                } else {
                    WidgetStateMessage(title: "No todos today", message: "Approved todos due or scheduled today will appear here.")
                        .padding(.top, 6)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(16)
    }
}

private struct TodayFocusBlock: View {
    let task: WidgetTask

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Now")
                .lisdoEyebrow(size: 8)

            Text(task.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LisdoColor.ink)
                .lineLimit(2)
                .lineSpacing(1)

            TodayTodoMetadata(task: task)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(LisdoColor.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LisdoColor.divider, lineWidth: 1)
        }
    }
}

private struct TodayTodoRow: View {
    let task: WidgetTask

    var body: some View {
        HStack(spacing: 8) {
            StatusCircle(isDraft: false, isActive: task.isInProgress)
            CategoryDot(categoryId: task.categoryId)

            Text(task.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LisdoColor.ink)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(task.metadata)
                .font(.system(size: 10))
                .foregroundStyle(LisdoColor.secondaryInk)
                .lineLimit(1)
        }
    }
}

private struct TodayTodoMetadata: View {
    let task: WidgetTask
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            CategoryDot(categoryId: task.categoryId)

            if compact {
                Text(task.compactMetadata)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(LisdoColor.secondaryInk)
                    .lineLimit(1)
            } else {
                Text(task.categoryName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LisdoColor.secondaryInk)
                    .lineLimit(1)

                Text("·")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LisdoColor.ink4)

                Text(task.metadata)
                    .font(.system(size: 11))
                    .foregroundStyle(LisdoColor.secondaryInk)
                    .lineLimit(1)
            }
        }
    }
}

private extension LisdoWidgetEntry {
    var closestTodayTodo: WidgetTask? {
        todayItems.first
    }

    var todayCountText: String {
        todayTodoCount == 1 ? "1 left" : "\(todayTodoCount) left"
    }

    var shortDateText: String {
        Self.shortDateFormatter.string(from: date)
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter
    }()
}

private extension WidgetTask {
    var compactMetadata: String {
        guard metadata != "Saved" else {
            return categoryName
        }

        return "\(categoryName) · \(metadata)"
    }
}

private struct WidgetStateMessage: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LisdoColor.ink)
                .lineLimit(2)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(LisdoColor.secondaryInk)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatusCircle: View {
    let isDraft: Bool
    var isActive = false
    var isFailed = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    strokeColor,
                    style: StrokeStyle(lineWidth: 1.4, dash: isDraft || isFailed ? [3, 2] : [])
                )
            if isActive {
                Circle()
                    .fill(LisdoColor.ink)
                    .padding(4)
            }
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }

    private var strokeColor: Color {
        if isFailed {
            return LisdoColor.warn
        }

        return isDraft ? LisdoColor.ink.opacity(0.32) : LisdoColor.ink5
    }
}

private struct CategoryDot: View {
    let categoryId: String?

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch categoryId {
        case "work", "lisdo.default.work":
            LisdoColor.info
        case "shopping", "lisdo.default.shopping":
            Color(red: 0.42, green: 0.35, blue: 0.29)
        case "research", "lisdo.default.research":
            Color(red: 0.31, green: 0.36, blue: 0.29)
        case "personal", "lisdo.default.personal":
            Color(red: 0.43, green: 0.36, blue: 0.48)
        case "home", "lisdo.default.errands":
            LisdoColor.ink4
        default:
            LisdoColor.ink
        }
    }
}

struct LisdoTaskActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LisdoActiveTaskActivityAttributes.self) { context in
            LockScreenLiveActivity(context: context)
                .activityBackgroundTint(LisdoColor.ink)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lisdo")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(context.attributes.category)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.compactProgressText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.activeTaskTitle)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(context.state.currentStep)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let nextStep = context.state.nextStep {
                            Text("Next: \(nextStep)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "checklist")
                    .font(.caption2.weight(.semibold))
            } compactTrailing: {
                Text(context.state.compactProgressText)
                    .font(.caption2.weight(.semibold))
            } minimal: {
                Image(systemName: "checkmark.circle")
                    .font(.caption2.weight(.semibold))
            }
        }
    }
}

struct LisdoPomodoroActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LisdoPomodoroActivityAttributes.self) { context in
            PomodoroLockScreenActivity(context: context)
                .activityBackgroundTint(LisdoColor.surface)
                .activitySystemActionForegroundColor(LisdoColor.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lisdo")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(context.attributes.categoryName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PomodoroRemainingText(state: context.state)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text("\(context.state.phase) focus session")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .font(.caption2.weight(.semibold))
            } compactTrailing: {
                PomodoroRemainingText(state: context.state)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "timer")
                    .font(.caption2.weight(.semibold))
            }
        }
    }
}

private struct LockScreenLiveActivity: View {
    let context: ActivityViewContext<LisdoActiveTaskActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LisdoColor.ink)
                    .frame(width: 22, height: 22)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text("Lisdo · In progress")
                    .font(.system(size: 11, weight: .medium))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.62))

                Spacer(minLength: 6)

                Text(context.attributes.category)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }

            Text(context.attributes.activeTaskTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)

            ProgressView(value: context.state.progress)
                .tint(.white)
                .scaleEffect(x: 1, y: 0.72, anchor: .center)

            HStack(alignment: .center, spacing: 9) {
                Circle()
                    .stroke(.white.opacity(0.5), lineWidth: 1.4)
                    .frame(width: 14, height: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(context.state.progressLabel) · Now")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                    Text(context.state.currentStep)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let nextStep = context.state.nextStep {
                    Text("Next: \(nextStep)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
    }
}

private struct PomodoroLockScreenActivity: View {
    let context: ActivityViewContext<LisdoPomodoroActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(LisdoColor.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text("Lisdo · \(context.state.phase)")
                    .font(.system(size: 11, weight: .medium))
                    .textCase(.uppercase)
                    .foregroundStyle(LisdoColor.secondaryInk)

                Spacer(minLength: 6)

                Text(context.attributes.categoryName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LisdoColor.secondaryInk)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LisdoColor.ink)
                        .lineLimit(2)
                    Text(context.state.isRunning ? "Focus timer running" : "Timer paused")
                        .font(.system(size: 12))
                        .foregroundStyle(LisdoColor.secondaryInk)
                }

                Spacer(minLength: 10)

                PomodoroRemainingText(state: context.state)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(LisdoColor.ink)
            }

            ProgressView(value: context.state.progress)
                .tint(LisdoColor.ink)
                .scaleEffect(x: 1, y: 0.7, anchor: .center)
        }
        .padding(14)
    }
}

private struct PomodoroRemainingText: View {
    let state: LisdoPomodoroActivityAttributes.ContentState

    var body: some View {
        if state.isRunning, let endDate = state.endDate, endDate > Date() {
            Text(timerInterval: Date()...endDate, countsDown: true)
        } else {
            Text(Self.formatTime(state.remainingSeconds))
        }
    }

    private static func formatTime(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded(.up)), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private extension LisdoActiveTaskActivityAttributes.ContentState {
    var compactProgressText: String {
        guard totalStepCount > 0 else {
            return "0"
        }

        let currentDisplayStep = min(completedStepCount + 1, totalStepCount)
        return "\(currentDisplayStep)/\(totalStepCount)"
    }
}

private extension LisdoPomodoroActivityAttributes.ContentState {
    var progress: Double {
        min(max(1 - (remainingSeconds / totalSeconds), 0), 1)
    }
}

private enum LisdoColor {
    static let surface = Color.white
    static let surface2 = Color(red: 0.98, green: 0.98, blue: 0.976)
    static let divider = Color(red: 0.898, green: 0.898, blue: 0.898)
    static let ink = Color(red: 0.055, green: 0.055, blue: 0.055)
    static let secondaryInk = Color(red: 0.431, green: 0.431, blue: 0.451)
    static let ink4 = Color(red: 0.631, green: 0.631, blue: 0.651)
    static let ink5 = Color(red: 0.780, green: 0.780, blue: 0.800)
    static let info = Color(red: 0.208, green: 0.361, blue: 0.541)
    static let warn = Color(red: 0.710, green: 0.396, blue: 0.114)
}

private extension Text {
    func lisdoEyebrow(size: CGFloat = 9) -> some View {
        font(.system(size: size, weight: .medium))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(LisdoColor.secondaryInk)
    }
}

@main
struct LisdoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LisdoTodayWidget()
        LisdoTaskActivity()
        LisdoPomodoroActivity()
    }
}
