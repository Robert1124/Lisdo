import LisdoCore
import SwiftData
import SwiftUI

struct PlanView: View {
    @Environment(\.modelContext) private var modelContext

    var todos: [Todo]
    var openPomodoro: (Todo) -> Void = { _ in }

    @Query(sort: \Category.name) private var categories: [Category]

    @State private var planMessage: String?
    @State private var selectedMode: PlanCalendarMode = .week
    @State private var selectedDate: Date = Date()

    private let calendar = Calendar.current
    private var now: Date { Date() }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header
                calendarBand
                planSummary
                if let planMessage {
                    ProductStateRow(icon: "checkmark.circle", title: "Plan update", message: planMessage)
                }
                planSections
            }
            .padding(16)
        }
        .background(LisdoTheme.surface)
        .navigationTitle("Plan")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Plan")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(LisdoTheme.ink1)
            Text("Lisdo-only due and scheduled work. No Calendar or Reminders sync.")
                .font(.system(size: 13))
                .foregroundStyle(LisdoTheme.ink3)
        }
        .padding(.horizontal, 4)
    }

    private var calendarBand: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Plan view", selection: $selectedMode) {
                ForEach(PlanCalendarMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 10) {
                Button {
                    shiftSelection(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous \(selectedMode.label)")

                Text(periodTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LisdoTheme.ink1)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)

                Button {
                    shiftSelection(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next \(selectedMode.label)")
            }

            switch selectedMode {
            case .day:
                dayCalendar
            case .week:
                weekCalendar
            case .month:
                monthCalendar
            }
        }
        .lisdoCard(padding: 12)
    }

    private var dayCalendar: some View {
        HStack(spacing: 5) {
            ForEach(weekDates(for: selectedDate), id: \.self) { date in
                PlanCalendarDayTile(
                    date: date,
                    isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                    isToday: calendar.isDateInToday(date),
                    hasItems: hasPlanItems(on: date),
                    compact: true
                ) {
                    selectedDate = date
                }
            }
        }
    }

    private var weekCalendar: some View {
        HStack(spacing: 5) {
            ForEach(weekDates(for: selectedDate), id: \.self) { date in
                PlanCalendarDayTile(
                    date: date,
                    isSelected: false,
                    isToday: calendar.isDateInToday(date),
                    hasItems: hasPlanItems(on: date),
                    compact: true
                ) {
                    selectedDate = date
                    selectedMode = .day
                }
            }
        }
    }

    private var monthCalendar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(weekDates(for: selectedDate), id: \.self) { date in
                    Text(date.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 10, weight: .medium))
                        .textCase(.uppercase)
                        .foregroundStyle(LisdoTheme.ink4)
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach(monthWeeks, id: \.self) { week in
                Button {
                    selectedDate = week.first ?? selectedDate
                    selectedMode = .week
                } label: {
                    HStack(spacing: 4) {
                        ForEach(week, id: \.self) { date in
                            PlanCalendarMonthDayCell(
                                date: date,
                                isCurrentMonth: calendar.isDate(date, equalTo: selectedDate, toGranularity: .month),
                                isToday: calendar.isDateInToday(date),
                                isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                                hasItems: hasPlanItems(on: date)
                            )
                        }
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open week of \(week.first?.formatted(.dateTime.month(.abbreviated).day()) ?? "selected date")")
            }
        }
    }

    private var planSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PlanMetricView(icon: "checkmark.circle", value: "\(plan.activeTodoCount)", label: "active")
                PlanMetricView(icon: "exclamationmark.circle", value: "\(bucketCount(.overdue))", label: "overdue")
                PlanMetricView(icon: "tray", value: "\(bucketCount(.noDate))", label: "no date")
            }

            HStack(spacing: 10) {
                PrioritySummaryView(summary: plan.prioritySummary)
                CategorySummaryView(summaries: plan.categorySummaries)
            }
        }
    }

    @ViewBuilder
    private var planSections: some View {
        if selectedPlanItems.isEmpty {
            Section {
                ProductStateRow(
                    icon: "calendar",
                    title: "No todos in this \(selectedMode.emptyScopeLabel)",
                    message: "Approved open or in-progress todos with Lisdo due or scheduled dates appear here for the selected \(selectedMode.emptyScopeLabel)."
                )
            } header: {
                LisdoSectionHeader(title: selectedMode.todoSectionTitle, detail: "0 active")
            }
        } else {
            Section {
                LazyVStack(spacing: 10) {
                    ForEach(selectedPlanItems) { item in
                        PlanTodoRow(
                            todo: item.todo,
                            bucketKind: item.bucketKind,
                            categoryName: categoryName(for: item.todo.categoryId),
                            calendar: calendar,
                            now: now,
                            onStartFocus: { startPomodoro(item.todo) },
                            onToggleCompletion: { toggleCompletion(item.todo) },
                            onDelete: { deleteTodo(item.todo) }
                        )
                    }
                }
            } header: {
                LisdoSectionHeader(title: selectedMode.todoSectionTitle, detail: "\(selectedPlanItems.count) active")
                    .padding(.top, 2)
            }
        }
    }

    private var plan: AdvancedPlanSnapshot {
        AdvancedPlanBuilder.makeSnapshot(todos: todos, categories: categories, calendar: calendar, now: now)
    }

    private var selectedPlanItems: [PlanDisplayTodo] {
        plan.buckets.flatMap { bucket in
            bucket.todos.map { PlanDisplayTodo(todo: $0, bucketKind: bucket.kind) }
        }
        .filter { item in
            guard let itemDate = item.relevantDate else {
                return false
            }

            switch selectedMode {
            case .day:
                guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
                    return false
                }
                return interval.contains(itemDate)
            case .week:
                guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
                    return false
                }
                return interval.contains(itemDate)
            case .month:
                return calendar.isDate(itemDate, equalTo: selectedDate, toGranularity: .month)
            }
        }
    }

    private var periodTitle: String {
        switch selectedMode {
        case .day:
            return selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        case .week:
            let dates = weekDates(for: selectedDate)
            guard let first = dates.first, let last = dates.last else {
                return "Selected week"
            }
            return "\(first.formatted(.dateTime.month(.abbreviated).day())) - \(last.formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            return selectedDate.formatted(.dateTime.month(.wide).year())
        }
    }

    private var monthWeeks: [[Date]] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate),
              var weekStart = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start)?.start
        else {
            return []
        }

        let lastMonthDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) ?? monthInterval.start
        let gridEnd = calendar.dateInterval(of: .weekOfYear, for: lastMonthDay)?.end ?? monthInterval.end
        var weeks: [[Date]] = []

        while weekStart < gridEnd {
            let week = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
            weeks.append(week)
            guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) else {
                break
            }
            weekStart = nextWeek
        }

        return weeks
    }

    private func weekDates(for date: Date) -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func shiftSelection(by value: Int) {
        let component: Calendar.Component = switch selectedMode {
        case .day:
            .day
        case .week:
            .weekOfYear
        case .month:
            .month
        }

        selectedDate = calendar.date(byAdding: component, value: value, to: selectedDate) ?? selectedDate
    }

    private func hasPlanItems(on date: Date) -> Bool {
        plan.buckets.contains { bucket in
            bucket.todos.contains { todo in
                guard let itemDate = todo.scheduledDate ?? todo.dueDate else { return false }
                return calendar.isDate(itemDate, inSameDayAs: date)
            }
        }
    }

    private func bucketCount(_ kind: AdvancedPlanBucketKind) -> Int {
        plan.buckets.first { $0.kind == kind }?.todos.count ?? 0
    }

    private func categoryName(for id: String?) -> String {
        categories.first(where: { $0.id == id })?.name ?? "General"
    }

    private func startPomodoro(_ snapshot: AdvancedPlanTodoSnapshot) {
        guard let todo = todos.first(where: { $0.id == snapshot.id }) else {
            planMessage = "This todo is no longer available on this device."
            return
        }

        openPomodoro(todo)
    }

    private func toggleCompletion(_ snapshot: AdvancedPlanTodoSnapshot) {
        guard let todo = todos.first(where: { $0.id == snapshot.id }) else {
            planMessage = "This todo is no longer available on this device."
            return
        }

        CaptureBatchActions.toggleSavedTodoCompletion(todo)
        do {
            try modelContext.save()
            planMessage = todo.status == .completed ? "Completed todo." : "Reopened todo."
        } catch {
            planMessage = "Could not update todo: \(error.localizedDescription)"
        }
    }

    private func deleteTodo(_ snapshot: AdvancedPlanTodoSnapshot) {
        guard let todo = todos.first(where: { $0.id == snapshot.id }) else {
            planMessage = "This todo is no longer available on this device."
            return
        }

        modelContext.delete(todo)
        do {
            try modelContext.save()
            planMessage = "Deleted todo."
        } catch {
            planMessage = "Could not delete todo: \(error.localizedDescription)"
        }
    }
}

private struct PlanMetricView: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(LisdoTheme.ink3)
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(LisdoTheme.ink1)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(LisdoTheme.ink3)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lisdoCard(padding: 12)
    }
}

private struct PrioritySummaryView: View {
    let summary: AdvancedPlanPrioritySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Priority", systemImage: "flag")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LisdoTheme.ink3)
            Text("High \(summary.high) · Medium \(summary.medium) · Low \(summary.low) · None \(summary.none)")
                .font(.system(size: 12))
                .foregroundStyle(LisdoTheme.ink2)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lisdoCard(padding: 12)
    }
}

private struct CategorySummaryView: View {
    let summaries: [AdvancedPlanCategorySummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Categories", systemImage: "square.grid.2x2")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LisdoTheme.ink3)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(LisdoTheme.ink2)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lisdoCard(padding: 12)
    }

    private var label: String {
        if summaries.isEmpty { return "No active categories" }
        return summaries.prefix(3).map { "\($0.categoryName) \($0.count)" }.joined(separator: " · ")
    }
}

private struct PlanSectionHeader: View {
    let bucket: AdvancedPlanBucket
    let calendar: Calendar
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LisdoTheme.ink1)
                Spacer()
                Text(countLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(LisdoTheme.ink3)
            }

            HStack(spacing: 8) {
                Text(kindLabel.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.7)
                    .foregroundStyle(LisdoTheme.ink3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(LisdoTheme.surface3, in: Capsule())

                Text(detailLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(LisdoTheme.ink3)
            }
        }
        .padding(.horizontal, 4)
    }

    private var title: String {
        switch bucket.kind {
        case .overdue: "Overdue"
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .noDate: "No date"
        }
    }

    private var countLabel: String {
        let count = bucket.todos.count
        return count == 1 ? "1 todo" : "\(count) todos"
    }

    private var detailLabel: String {
        switch bucket.kind {
        case .overdue: "Past due or scheduled before today."
        case .today: "Due or scheduled today."
        case .upcoming: "Future Lisdo dates only."
        case .noDate: "Approved todos without a resolved date."
        }
    }

    private var kindLabel: String {
        switch bucket.kind {
        case .overdue: "Overdue"
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .noDate: "No date"
        }
    }
}

private struct PlanTodoRow: View {
    let todo: AdvancedPlanTodoSnapshot
    let bucketKind: AdvancedPlanBucketKind
    let categoryName: String
    let calendar: Calendar
    let now: Date
    var onStartFocus: () -> Void
    var onToggleCompletion: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button(action: onToggleCompletion) {
                    TodoStatusMark(status: todo.status)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(todo.status == .completed ? "Reopen todo" : "Complete todo")

                Text(todo.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LisdoTheme.ink1)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Button(action: onStartFocus) {
                    Label(todo.status == .inProgress ? "Focus" : "Start", systemImage: "timer")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(LisdoTheme.ink3)
                .accessibilityLabel(todo.status == .inProgress ? "Open Pomodoro" : "Start Pomodoro")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(LisdoTheme.ink3)
                .accessibilityLabel("Delete todo")
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    LisdoCategoryDot(categoryId: todo.categoryId)
                    Text(categoryName.uppercased())
                }

                PlanMetadataDivider()

                Label(timingLabel, systemImage: timingIcon)

                if let priority = todo.priority {
                    PlanMetadataDivider()
                    Text(priorityLabel(priority))
                }

                Spacer(minLength: 0)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(LisdoTheme.ink3)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lisdoCard(padding: 13)
        .contextMenu {
            Button(action: onStartFocus) {
                Label(todo.status == .inProgress ? "Open Pomodoro" : "Start Pomodoro", systemImage: "timer")
            }

            Button(action: onToggleCompletion) {
                Label(todo.status == .completed ? "Reopen Todo" : "Complete Todo", systemImage: todo.status == .completed ? "circle" : "checkmark.circle")
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete Todo", systemImage: "trash")
            }
        }
    }

    private var timingIcon: String {
        switch bucketKind {
        case .overdue: "exclamationmark.circle"
        case .today, .upcoming: "calendar"
        case .noDate: "tray"
        }
    }

    private var timingLabel: String {
        if let scheduledDate = todo.scheduledDate {
            return "Scheduled \(dateLabel(for: scheduledDate))"
        }
        if let dueDate = todo.dueDate {
            return "Due \(dateLabel(for: dueDate))"
        }
        return "No date"
    }

    private func dateLabel(for date: Date) -> String {
        let includesTime = calendar.component(.hour, from: date) != 0
            || calendar.component(.minute, from: date) != 0

        if calendar.isDateInToday(date) {
            return includesTime
                ? "today, \(date.formatted(.dateTime.hour().minute()))"
                : "today"
        }

        if calendar.isDateInTomorrow(date) {
            return includesTime
                ? "tomorrow, \(date.formatted(.dateTime.hour().minute()))"
                : "tomorrow"
        }

        return includesTime
            ? date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
            : date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func priorityLabel(_ priority: TodoPriority) -> String {
        switch priority {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }
}

private struct PlanMetadataDivider: View {
    var body: some View {
        Circle()
            .fill(LisdoTheme.ink5)
            .frame(width: 3, height: 3)
    }
}

private struct PlanDisplayTodo: Identifiable {
    let todo: AdvancedPlanTodoSnapshot
    let bucketKind: AdvancedPlanBucketKind

    var id: UUID { todo.id }

    var relevantDate: Date? {
        todo.scheduledDate ?? todo.dueDate
    }
}

private enum PlanCalendarMode: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day:
            return "Day"
        case .week:
            return "Week"
        case .month:
            return "Month"
        }
    }

    var todoSectionTitle: String {
        switch self {
        case .day:
            return "Selected day"
        case .week:
            return "Selected week"
        case .month:
            return "Selected month"
        }
    }

    var emptyScopeLabel: String {
        switch self {
        case .day:
            return "week"
        case .week:
            return "week"
        case .month:
            return "month"
        }
    }
}

private struct PlanCalendarDayTile: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let hasItems: Bool
    let compact: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: compact ? 5 : 8) {
                Text(date.formatted(.dateTime.weekday(compact ? .narrow : .wide)))
                    .font(.system(size: compact ? 10 : 12, weight: .medium))
                    .textCase(.uppercase)
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: compact ? 17 : 30, weight: .semibold))
                Circle()
                    .fill(hasItems ? dotColor : Color.clear)
                    .frame(width: compact ? 4 : 5, height: compact ? 4 : 5)
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 8 : 16)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous)
                    .stroke(isSelected && !isToday ? LisdoTheme.ink3.opacity(0.45) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
    }

    private var foregroundColor: Color {
        isToday ? LisdoTheme.onAccent : LisdoTheme.ink2
    }

    private var backgroundColor: Color {
        if isToday {
            return LisdoTheme.ink1
        }
        return isSelected ? LisdoTheme.surface3 : Color.clear
    }

    private var dotColor: Color {
        isToday ? LisdoTheme.onAccent : LisdoTheme.ink3
    }
}

private struct PlanCalendarMonthDayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let hasItems: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 12, weight: isToday || isSelected ? .semibold : .regular))
                .foregroundStyle(textColor)
            Circle()
                .fill(hasItems ? dotColor : Color.clear)
                .frame(width: 3, height: 3)
        }
        .frame(maxWidth: .infinity, minHeight: 30)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var textColor: Color {
        if isToday {
            return LisdoTheme.onAccent
        }
        return isCurrentMonth ? LisdoTheme.ink2 : LisdoTheme.ink5
    }

    private var dotColor: Color {
        isToday ? LisdoTheme.onAccent : LisdoTheme.ink3
    }

    private var backgroundColor: Color {
        if isToday {
            return LisdoTheme.ink1
        }
        return isSelected ? LisdoTheme.surface3 : Color.clear
    }
}
