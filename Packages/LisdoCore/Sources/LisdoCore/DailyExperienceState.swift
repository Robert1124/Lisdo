import Foundation

public enum DailyPlanSectionKind: Equatable, Hashable, Sendable {
    case scheduledDate(Date)
    case dueDate(Date)
    case naturalDueDateText(Date)
    case noDate
}

public struct DailyPlanTodoSnapshot: Equatable, Sendable {
    public var id: UUID
    public var categoryId: String
    public var title: String
    public var summary: String?
    public var status: TodoStatus
    public var dueDate: Date?
    public var dueDateText: String?
    public var scheduledDate: Date?
    public var priority: TodoPriority?

    public init(
        id: UUID,
        categoryId: String,
        title: String,
        summary: String?,
        status: TodoStatus,
        dueDate: Date?,
        dueDateText: String?,
        scheduledDate: Date?,
        priority: TodoPriority?
    ) {
        self.id = id
        self.categoryId = categoryId
        self.title = title
        self.summary = summary
        self.status = status
        self.dueDate = dueDate
        self.dueDateText = dueDateText
        self.scheduledDate = scheduledDate
        self.priority = priority
    }
}

public struct DailyPlanSection: Equatable, Sendable {
    public var kind: DailyPlanSectionKind
    public var title: String
    public var date: Date?
    public var todos: [DailyPlanTodoSnapshot]

    public init(kind: DailyPlanSectionKind, title: String, date: Date?, todos: [DailyPlanTodoSnapshot]) {
        self.kind = kind
        self.title = title
        self.date = date
        self.todos = todos
    }
}

public struct DailyPlanSnapshot: Equatable, Sendable {
    public var generatedAt: Date
    public var activeTodoCount: Int
    public var sections: [DailyPlanSection]

    public init(generatedAt: Date, activeTodoCount: Int, sections: [DailyPlanSection]) {
        self.generatedAt = generatedAt
        self.activeTodoCount = activeTodoCount
        self.sections = sections
    }
}

public struct ActiveTaskStepSnapshot: Equatable, Sendable {
    public var blockId: UUID
    public var type: TodoBlockType
    public var content: String
    public var checked: Bool
    public var order: Int

    public init(blockId: UUID, type: TodoBlockType, content: String, checked: Bool, order: Int) {
        self.blockId = blockId
        self.type = type
        self.content = content
        self.checked = checked
        self.order = order
    }
}

public struct ActiveTaskSnapshot: Equatable, Sendable {
    public var todoId: UUID
    public var categoryId: String
    public var title: String
    public var summary: String?
    public var currentStep: ActiveTaskStepSnapshot?
    public var nextStep: ActiveTaskStepSnapshot?
    public var completedStepCount: Int
    public var totalStepCount: Int
    public var progressLabel: String
    public var isComplete: Bool

    public init(
        todoId: UUID,
        categoryId: String,
        title: String,
        summary: String?,
        currentStep: ActiveTaskStepSnapshot?,
        nextStep: ActiveTaskStepSnapshot?,
        completedStepCount: Int,
        totalStepCount: Int,
        progressLabel: String,
        isComplete: Bool
    ) {
        self.todoId = todoId
        self.categoryId = categoryId
        self.title = title
        self.summary = summary
        self.currentStep = currentStep
        self.nextStep = nextStep
        self.completedStepCount = completedStepCount
        self.totalStepCount = totalStepCount
        self.progressLabel = progressLabel
        self.isComplete = isComplete
    }
}

public struct DailyWidgetSnapshot: Equatable, Sendable {
    public var generatedAt: Date
    public var todayTodoCount: Int
    public var noDateTodoCount: Int
    public var activeTask: ActiveTaskSnapshot?

    public init(generatedAt: Date, todayTodoCount: Int, noDateTodoCount: Int, activeTask: ActiveTaskSnapshot?) {
        self.generatedAt = generatedAt
        self.todayTodoCount = todayTodoCount
        self.noDateTodoCount = noDateTodoCount
        self.activeTask = activeTask
    }
}

public enum DailyExperienceState {
    public static func makePlan(
        todos: [Todo],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> DailyPlanSnapshot {
        let activeTodos = todos.filter(\.isDailyExperienceActive)
        let sectioned = Dictionary(grouping: activeTodos) { todo in
            sectionKind(for: todo, calendar: calendar, now: now)
        }

        let sections = sectioned
            .map { kind, todos in
                DailyPlanSection(
                    kind: kind,
                    title: title(for: kind, calendar: calendar, now: now),
                    date: kind.date,
                    todos: todos.sortedForDailyExperience().map(DailyPlanTodoSnapshot.init)
                )
            }
            .sorted { lhs, rhs in
                compare(lhs.kind, rhs.kind) == .orderedAscending
            }

        return DailyPlanSnapshot(
            generatedAt: now,
            activeTodoCount: activeTodos.count,
            sections: sections
        )
    }

    public static func activeTask(from todos: [Todo]) -> ActiveTaskSnapshot? {
        todos
            .filter { $0.status == .inProgress }
            .sortedForDailyExperience()
            .first
            .map(makeActiveTaskSnapshot)
    }

    public static func liveActivitySnapshot(from todos: [Todo]) -> ActiveTaskSnapshot? {
        activeTask(from: todos)
    }

    public static func widgetSnapshot(
        todos: [Todo],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> DailyWidgetSnapshot {
        let plan = makePlan(todos: todos, calendar: calendar, now: now)
        let today = calendar.startOfDay(for: now)
        let todayCount = plan.sections
            .filter { $0.date == today }
            .reduce(0) { count, section in count + section.todos.count }
        let noDateCount = plan.sections
            .first { $0.kind == .noDate }?
            .todos
            .count ?? 0

        return DailyWidgetSnapshot(
            generatedAt: now,
            todayTodoCount: todayCount,
            noDateTodoCount: noDateCount,
            activeTask: activeTask(from: todos)
        )
    }

    private static func makeActiveTaskSnapshot(for todo: Todo) -> ActiveTaskSnapshot {
        let steps = (todo.blocks ?? [])
            .sortedForDailyExperience()
            .map(ActiveTaskStepSnapshot.init)
        let completedCount = steps.filter(\.checked).count
        let currentIndex = steps.firstIndex { !$0.checked }
        let currentStep = currentIndex.map { steps[$0] }
        let nextStep = currentIndex.flatMap { index in
            steps.dropFirst(index + 1).first { !$0.checked }
        }

        return ActiveTaskSnapshot(
            todoId: todo.id,
            categoryId: todo.categoryId,
            title: todo.title,
            summary: todo.summary,
            currentStep: currentStep,
            nextStep: nextStep,
            completedStepCount: completedCount,
            totalStepCount: steps.count,
            progressLabel: progressLabel(totalStepCount: steps.count, currentIndex: currentIndex),
            isComplete: !steps.isEmpty && currentIndex == nil
        )
    }

    private static func progressLabel(totalStepCount: Int, currentIndex: Int?) -> String {
        guard totalStepCount > 0 else {
            return "No steps"
        }

        guard let currentIndex else {
            let noun = totalStepCount == 1 ? "step" : "steps"
            return "All \(totalStepCount) \(noun) complete"
        }

        return "Step \(currentIndex + 1) of \(totalStepCount)"
    }

    private static func sectionKind(for todo: Todo, calendar: Calendar, now: Date) -> DailyPlanSectionKind {
        if let scheduledDate = todo.scheduledDate {
            return .scheduledDate(calendar.startOfDay(for: scheduledDate))
        }

        if let dueDate = todo.dueDate {
            return .dueDate(calendar.startOfDay(for: dueDate))
        }

        if let dueDateText = todo.dueDateText?.trimmingCharacters(in: .whitespacesAndNewlines), !dueDateText.isEmpty {
            let lowercased = dueDateText.lowercased()
            let today = calendar.startOfDay(for: now)

            if lowercased.contains("today") {
                return .naturalDueDateText(today)
            }

            if lowercased.contains("tomorrow"),
               let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) {
                return .naturalDueDateText(tomorrow)
            }
        }

        return .noDate
    }

    private static func title(for kind: DailyPlanSectionKind, calendar: Calendar, now: Date) -> String {
        switch kind {
        case .scheduledDate(let date):
            return dateTitle(prefix: "Scheduled", date: date, calendar: calendar, now: now)
        case .dueDate(let date):
            return dateTitle(prefix: "Due", date: date, calendar: calendar, now: now)
        case .naturalDueDateText(let date):
            return dateTitle(prefix: "Due", date: date, calendar: calendar, now: now)
        case .noDate:
            return "No date"
        }
    }

    private static func dateTitle(prefix: String, date: Date, calendar: Calendar, now: Date) -> String {
        let today = calendar.startOfDay(for: now)

        if date == today {
            return "\(prefix) today"
        }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), date == tomorrow {
            return "\(prefix) tomorrow"
        }

        return prefix
    }

    private static func compare(_ lhs: DailyPlanSectionKind, _ rhs: DailyPlanSectionKind) -> ComparisonResult {
        switch (lhs.date, rhs.date) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate < rhsDate ? .orderedAscending : .orderedDescending
        case (nil, _?):
            return .orderedDescending
        case (_?, nil):
            return .orderedAscending
        default:
            return lhs.sortOrder < rhs.sortOrder ? .orderedAscending : .orderedDescending
        }
    }
}

private extension DailyPlanSectionKind {
    var date: Date? {
        switch self {
        case .scheduledDate(let date), .dueDate(let date), .naturalDueDateText(let date):
            return date
        case .noDate:
            return nil
        }
    }

    var sortOrder: Int {
        switch self {
        case .scheduledDate:
            return 0
        case .dueDate:
            return 1
        case .naturalDueDateText:
            return 2
        case .noDate:
            return 3
        }
    }
}

private extension Todo {
    var isDailyExperienceActive: Bool {
        status == .open || status == .inProgress
    }
}

private extension DailyPlanTodoSnapshot {
    init(_ todo: Todo) {
        self.init(
            id: todo.id,
            categoryId: todo.categoryId,
            title: todo.title,
            summary: todo.summary,
            status: todo.status,
            dueDate: todo.dueDate,
            dueDateText: todo.dueDateText,
            scheduledDate: todo.scheduledDate,
            priority: todo.priority
        )
    }
}

private extension ActiveTaskStepSnapshot {
    init(_ block: TodoBlock) {
        self.init(
            blockId: block.id,
            type: block.type,
            content: block.content,
            checked: block.checked,
            order: block.order
        )
    }
}

private extension Array where Element == Todo {
    func sortedForDailyExperience() -> [Todo] {
        sorted { lhs, rhs in
            let lhsDate = lhs.scheduledDate ?? lhs.dueDate
            let rhsDate = rhs.scheduledDate ?? rhs.dueDate

            if lhsDate != rhsDate {
                switch (lhsDate, rhsDate) {
                case let (lhsDate?, rhsDate?):
                    return lhsDate < rhsDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }
            }

            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }

            if lhs.title != rhs.title {
                return lhs.title < rhs.title
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

private extension Array where Element == TodoBlock {
    func sortedForDailyExperience() -> [TodoBlock] {
        filter { $0.type == .checkbox }
            .sorted { lhs, rhs in
                if lhs.order != rhs.order {
                    return lhs.order < rhs.order
                }

                if lhs.content != rhs.content {
                    return lhs.content < rhs.content
                }

                return lhs.id.uuidString < rhs.id.uuidString
            }
    }
}
