import Foundation

public struct AdvancedSearchQuery: Equatable, Sendable {
    public var text: String?
    public var captureStatuses: Set<CaptureStatus>
    public var providerModes: Set<ProviderMode>
    public var categoryIds: Set<String>
    public var draftNeedsClarification: Bool?
    public var todoStatuses: Set<TodoStatus>
    public var priorities: Set<TodoPriority>

    public init(
        text: String? = nil,
        captureStatuses: Set<CaptureStatus> = [],
        providerModes: Set<ProviderMode> = [],
        categoryIds: Set<String> = [],
        draftNeedsClarification: Bool? = nil,
        todoStatuses: Set<TodoStatus> = [],
        priorities: Set<TodoPriority> = []
    ) {
        self.text = text
        self.captureStatuses = captureStatuses
        self.providerModes = providerModes
        self.categoryIds = categoryIds
        self.draftNeedsClarification = draftNeedsClarification
        self.todoStatuses = todoStatuses
        self.priorities = priorities
    }
}

public struct AdvancedSearchResult {
    public var captures: [CaptureItem]
    public var drafts: [ProcessingDraft]
    public var todos: [Todo]

    public init(captures: [CaptureItem], drafts: [ProcessingDraft], todos: [Todo]) {
        self.captures = captures
        self.drafts = drafts
        self.todos = todos
    }
}

public enum LisdoAdvancedSearch {
    public static func filter(
        captures: [CaptureItem],
        drafts: [ProcessingDraft],
        todos: [Todo],
        query: AdvancedSearchQuery
    ) -> AdvancedSearchResult {
        let tokens = searchTokens(from: query.text)

        return AdvancedSearchResult(
            captures: captures.filter { capture in
                matches(tokens: tokens, in: capture.searchableText)
                    && (query.captureStatuses.isEmpty || query.captureStatuses.contains(capture.status))
                    && (query.providerModes.isEmpty || query.providerModes.contains(capture.preferredProviderMode))
            },
            drafts: drafts.filter { draft in
                matches(tokens: tokens, in: draft.searchableText)
                    && (query.categoryIds.isEmpty || draft.recommendedCategoryId.map(query.categoryIds.contains) == true)
                    && (query.draftNeedsClarification == nil || draft.needsClarification == query.draftNeedsClarification)
            },
            todos: todos.filter { todo in
                matches(tokens: tokens, in: todo.searchableText)
                    && (query.categoryIds.isEmpty || query.categoryIds.contains(todo.categoryId))
                    && (query.todoStatuses.isEmpty || query.todoStatuses.contains(todo.status))
                    && (query.priorities.isEmpty || todo.priority.map(query.priorities.contains) == true)
            }
        )
    }

    private static func searchTokens(from text: String?) -> [String] {
        text?
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init) ?? []
    }

    private static func matches(tokens: [String], in text: String) -> Bool {
        guard !tokens.isEmpty else {
            return true
        }

        let lowercased = text.lowercased()
        return tokens.allSatisfy { lowercased.contains($0) }
    }
}

public enum CaptureBatchSelector {
    public static func processablePendingCaptures(from captures: [CaptureItem]) -> [CaptureItem] {
        captures.filter { capture in
            capture.status == .pendingProcessing || capture.status == .retryPending
        }
    }

    public static func failedCaptures(from captures: [CaptureItem]) -> [CaptureItem] {
        captures.filter { $0.status == .failed }
    }
}

public enum HostedProviderQueuePolicy {
    public static let hostedProviderModes: Set<ProviderMode> = [
        .openAICompatibleBYOK,
        .minimax,
        .anthropic,
        .gemini,
        .openRouter
    ]

    public static func isHostedProviderMode(_ mode: ProviderMode) -> Bool {
        hostedProviderModes.contains(mode)
    }

    public static func supportsDirectAttachments(_ mode: ProviderMode) -> Bool {
        switch mode {
        case .openAICompatibleBYOK, .minimax, .openRouter:
            return true
        case .anthropic, .gemini, .macOnlyCLI, .ollama, .lmStudio, .localModel:
            return false
        }
    }

    public static func isIPhoneHostedPendingCandidate(_ capture: CaptureItem) -> Bool {
        capture.createdDevice == .iPhone
            && isHostedProviderMode(capture.preferredProviderMode)
            && CaptureBatchSelector.processablePendingCaptures(from: [capture]).contains { $0.id == capture.id }
    }
}

public enum CaptureDeletionPolicy {
    public static func canDeleteCapture(_ capture: CaptureItem) -> Bool {
        capture.status != .approvedTodo
    }

    public static func captureIdsToDelete(
        whenDeleting draft: ProcessingDraft,
        captures: [CaptureItem]
    ) -> [UUID] {
        captures
            .filter { capture in
                capture.id == draft.captureItemId && canDeleteCapture(capture)
            }
            .map(\.id)
    }
}

public enum CaptureBatchActions {
    @discardableResult
    public static func queueFailedCapturesForRetry(_ captures: [CaptureItem]) throws -> [CaptureItem] {
        let failed = CaptureBatchSelector.failedCaptures(from: captures)
        for capture in failed {
            try capture.queueForRetry()
        }
        return failed
    }

    @discardableResult
    public static func archiveCompletedTodos(
        _ todos: [Todo],
        completedBefore cutoff: Date? = nil,
        archivedAt: Date = Date()
    ) -> [Todo] {
        let candidates = todos.filter { todo in
            guard todo.status == .completed else {
                return false
            }

            guard let cutoff else {
                return true
            }

            return todo.updatedAt < cutoff
        }

        for todo in candidates {
            todo.status = .archived
            todo.updatedAt = archivedAt
        }

        return candidates
    }

    public static func toggleSavedTodoCompletion(
        _ todo: Todo,
        updatedAt: Date = Date()
    ) {
        if todo.status == .completed {
            todo.status = .open
        } else {
            todo.status = .completed
            todo.blocks?.forEach { block in
                block.checked = true
            }
        }
        todo.updatedAt = updatedAt
    }
}

public enum TodoTrashPolicy {
    public static let retentionDays = 30

    @discardableResult
    public static func moveToTrash(
        _ todos: [Todo],
        trashedAt: Date = Date()
    ) -> [Todo] {
        let candidates = todos.filter { $0.status != .trashed }

        for todo in candidates {
            todo.status = .trashed
            todo.updatedAt = trashedAt
        }

        return candidates
    }

    public static func expiredTrashedTodos(
        _ todos: [Todo],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Todo] {
        let fallbackCutoff = now.addingTimeInterval(-Double(retentionDays) * 24 * 60 * 60)
        let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: now) ?? fallbackCutoff

        return todos.filter { todo in
            todo.status == .trashed && todo.updatedAt < cutoff
        }
    }
}

public enum LisdoCategorySmartListKind: String, CaseIterable, Sendable {
    case today
    case drafts
    case archive
    case trash
    case attention

    public static let defaultKinds: [LisdoCategorySmartListKind] = [
        .today,
        .drafts,
        .archive,
        .trash,
        .attention
    ]

    public var title: String {
        switch self {
        case .today:
            "Today"
        case .drafts:
            "AI Drafts"
        case .archive:
            "Archive"
        case .trash:
            "Trash"
        case .attention:
            "Needs attention"
        }
    }

    public var systemImage: String {
        switch self {
        case .today:
            "calendar"
        case .drafts:
            "sparkle"
        case .archive:
            "archivebox"
        case .trash:
            "trash"
        case .attention:
            "exclamationmark.circle"
        }
    }
}

public enum AdvancedPlanBucketKind: String, Codable, Equatable, Sendable {
    case overdue
    case today
    case upcoming
    case noDate
}

public struct AdvancedPlanTodoSnapshot: Equatable, Sendable {
    public var id: UUID
    public var categoryId: String
    public var title: String
    public var status: TodoStatus
    public var dueDate: Date?
    public var scheduledDate: Date?
    public var priority: TodoPriority?

    public init(todo: Todo) {
        self.id = todo.id
        self.categoryId = todo.categoryId
        self.title = todo.title
        self.status = todo.status
        self.dueDate = todo.dueDate
        self.scheduledDate = todo.scheduledDate
        self.priority = todo.priority
    }
}

public struct AdvancedPlanBucket: Equatable, Sendable {
    public var kind: AdvancedPlanBucketKind
    public var todos: [AdvancedPlanTodoSnapshot]

    public init(kind: AdvancedPlanBucketKind, todos: [AdvancedPlanTodoSnapshot]) {
        self.kind = kind
        self.todos = todos
    }
}

public struct AdvancedPlanPrioritySummary: Equatable, Sendable {
    public var high: Int
    public var medium: Int
    public var low: Int
    public var none: Int

    public init(high: Int = 0, medium: Int = 0, low: Int = 0, none: Int = 0) {
        self.high = high
        self.medium = medium
        self.low = low
        self.none = none
    }
}

public struct AdvancedPlanCategorySummary: Equatable, Sendable {
    public var categoryId: String
    public var categoryName: String
    public var count: Int

    public init(categoryId: String, categoryName: String, count: Int) {
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.count = count
    }
}

public struct AdvancedPlanSnapshot: Equatable, Sendable {
    public var generatedAt: Date
    public var activeTodoCount: Int
    public var buckets: [AdvancedPlanBucket]
    public var prioritySummary: AdvancedPlanPrioritySummary
    public var categorySummaries: [AdvancedPlanCategorySummary]

    public init(
        generatedAt: Date,
        activeTodoCount: Int,
        buckets: [AdvancedPlanBucket],
        prioritySummary: AdvancedPlanPrioritySummary,
        categorySummaries: [AdvancedPlanCategorySummary]
    ) {
        self.generatedAt = generatedAt
        self.activeTodoCount = activeTodoCount
        self.buckets = buckets
        self.prioritySummary = prioritySummary
        self.categorySummaries = categorySummaries
    }
}

public enum AdvancedPlanBuilder {
    public static func makeSnapshot(
        todos: [Todo],
        categories: [Category],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> AdvancedPlanSnapshot {
        let activeTodos = todos.filter { $0.status == .open || $0.status == .inProgress }
        let grouped = Dictionary(grouping: activeTodos) { todo in
            bucketKind(for: todo, calendar: calendar, now: now)
        }

        let buckets = AdvancedPlanBucketKind.displayOrder.compactMap { kind -> AdvancedPlanBucket? in
            guard let todos = grouped[kind], !todos.isEmpty else {
                return nil
            }

            return AdvancedPlanBucket(
                kind: kind,
                todos: todos.sortedForAdvancedPlan(calendar: calendar, now: now).map(AdvancedPlanTodoSnapshot.init)
            )
        }

        return AdvancedPlanSnapshot(
            generatedAt: now,
            activeTodoCount: activeTodos.count,
            buckets: buckets,
            prioritySummary: prioritySummary(for: activeTodos),
            categorySummaries: categorySummaries(for: activeTodos, categories: categories)
        )
    }

    private static func bucketKind(for todo: Todo, calendar: Calendar, now: Date) -> AdvancedPlanBucketKind {
        guard let relevantDate = todo.resolvedLisdoPlanDate(calendar: calendar, now: now) else {
            return .noDate
        }

        let today = calendar.startOfDay(for: now)
        let itemDay = calendar.startOfDay(for: relevantDate)

        if itemDay < today {
            return .overdue
        }

        if itemDay == today {
            return .today
        }

        return .upcoming
    }

    private static func prioritySummary(for todos: [Todo]) -> AdvancedPlanPrioritySummary {
        todos.reduce(into: AdvancedPlanPrioritySummary()) { summary, todo in
            switch todo.priority {
            case .high:
                summary.high += 1
            case .medium:
                summary.medium += 1
            case .low:
                summary.low += 1
            case nil:
                summary.none += 1
            }
        }
    }

    private static func categorySummaries(for todos: [Todo], categories: [Category]) -> [AdvancedPlanCategorySummary] {
        let categoryNames = Dictionary(
            categories.map { ($0.id, $0.name) },
            uniquingKeysWith: { existing, _ in existing }
        )
        return Dictionary(grouping: todos, by: \.categoryId)
            .map { categoryId, todos in
                AdvancedPlanCategorySummary(
                    categoryId: categoryId,
                    categoryName: categoryNames[categoryId] ?? categoryId,
                    count: todos.count
                )
            }
            .sorted { lhs, rhs in
                if lhs.categoryName != rhs.categoryName {
                    return lhs.categoryName < rhs.categoryName
                }
                return lhs.categoryId < rhs.categoryId
            }
    }
}

public extension Todo {
    func resolvedLisdoPlanDate(calendar: Calendar = .current, now: Date = Date()) -> Date? {
        if let scheduledDate {
            return scheduledDate
        }

        if let dueDate {
            return dueDate
        }

        guard let dueDateText = dueDateText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !dueDateText.isEmpty
        else {
            return nil
        }

        let lowercased = dueDateText.lowercased()
        let today = calendar.startOfDay(for: now)
        if lowercased.contains("today") || lowercased.contains("tonight") {
            return today
        }

        if lowercased.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: today)
        }

        return nil
    }
}

private extension AdvancedPlanBucketKind {
    static let displayOrder: [AdvancedPlanBucketKind] = [.overdue, .today, .upcoming, .noDate]
}

private extension CaptureItem {
    var searchableText: String {
        [
            sourceText,
            transcriptText,
            userNote,
            processingError,
            sourceType.rawValue,
            createdDevice.rawValue,
            status.rawValue,
            preferredProviderMode.rawValue
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }
}

private extension ProcessingDraft {
    var searchableText: String {
        [
            recommendedCategoryId,
            title,
            summary,
            dueDateText,
            priority?.rawValue,
            generatedByProvider,
            questionsForUser.joined(separator: " "),
            blocks.map(\.content).joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }
}

private extension Todo {
    var searchableText: String {
        [
            categoryId,
            title,
            summary,
            dueDateText,
            status.rawValue,
            priority?.rawValue,
            blocks?.map(\.content).joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }
}

private extension Array where Element == Todo {
    func sortedForAdvancedPlan(calendar: Calendar, now: Date) -> [Todo] {
        sorted { lhs, rhs in
            let lhsDate = lhs.resolvedLisdoPlanDate(calendar: calendar, now: now)
            let rhsDate = rhs.resolvedLisdoPlanDate(calendar: calendar, now: now)

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

            if lhs.title != rhs.title {
                return lhs.title < rhs.title
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
