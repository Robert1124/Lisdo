import Foundation
import LisdoCore
import SwiftData
import SwiftUI
import WidgetKit

struct LisdoWidgetEntry: TimelineEntry {
    let date: Date
    let state: WidgetDataState
    let todayTodoCount: Int
    let draftCount: Int
    let pendingCaptureCount: Int
    let failedCaptureCount: Int
    let focus: WidgetTask?
    let inboxItems: [WidgetInboxItem]
    let todayItems: [WidgetTask]
    let activeTask: WidgetActiveTask?

    static let preview = LisdoWidgetEntry(
        date: .now,
        state: .empty,
        todayTodoCount: 0,
        draftCount: 0,
        pendingCaptureCount: 0,
        failedCaptureCount: 0,
        focus: nil,
        inboxItems: [],
        todayItems: [],
        activeTask: nil
    )

    static func loading(date: Date = .now) -> LisdoWidgetEntry {
        LisdoWidgetEntry(
            date: date,
            state: .loading,
            todayTodoCount: 0,
            draftCount: 0,
            pendingCaptureCount: 0,
            failedCaptureCount: 0,
            focus: nil,
            inboxItems: [],
            todayItems: [],
            activeTask: nil
        )
    }

    static func error(date: Date = .now, message: String) -> LisdoWidgetEntry {
        LisdoWidgetEntry(
            date: date,
            state: .error(message),
            todayTodoCount: 0,
            draftCount: 0,
            pendingCaptureCount: 0,
            failedCaptureCount: 0,
            focus: nil,
            inboxItems: [],
            todayItems: [],
            activeTask: nil
        )
    }
}

enum WidgetDataState: Equatable {
    case loading
    case empty
    case content
    case error(String)
}

struct WidgetTask: Identifiable, Equatable {
    let id: String
    let title: String
    let metadata: String
    let categoryName: String
    let categoryId: String
    let status: TodoStatus

    var isInProgress: Bool {
        status == .inProgress
    }
}

struct WidgetInboxItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case draft
        case pending
        case failed
    }

    let id: String
    let title: String
    let metadata: String
    let categoryId: String?
    let kind: Kind
}

struct WidgetActiveTask: Equatable {
    let todoId: String
    let title: String
    let categoryName: String
    let categoryId: String
    let currentStepBlockId: String?
    let currentStep: String
    let nextStep: String?
    let progress: Double
    let progressLabel: String
}

enum LisdoWidgetDataStore {
    static let refreshInterval: TimeInterval = 10 * 60

    static func loadEntry(date: Date = .now) -> LisdoWidgetEntry {
        do {
            let context = try makeModelContext()
            let categories = try context.fetch(FetchDescriptor<LisdoCore.Category>(sortBy: [SortDescriptor(\.name)]))
            let drafts = try context.fetch(FetchDescriptor<ProcessingDraft>(sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]))
            let captures = try context.fetch(FetchDescriptor<CaptureItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
            let todos = try context.fetch(FetchDescriptor<Todo>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))

            return makeEntry(
                date: date,
                categories: categories,
                drafts: drafts,
                captures: captures,
                todos: todos
            )
        } catch {
            return .error(date: date, message: "Lisdo could not read iCloud task state.")
        }
    }

    @MainActor
    static func startTodo(idString: String) async throws {
        let context = try makeModelContext()
        let todos = try context.fetch(FetchDescriptor<Todo>())
        guard let todo = todos.todo(matching: idString), todo.status == .open || todo.status == .inProgress else {
            throw LisdoWidgetIntentError.todoUnavailable
        }

        let now = Date()
        for activeTodo in todos where activeTodo.status == .inProgress && activeTodo.id != todo.id {
            activeTodo.status = .open
            activeTodo.updatedAt = now
        }

        todo.status = .inProgress
        todo.updatedAt = now
        try context.save()

        let categoryName = try categoryName(for: todo.categoryId, in: context)
        await LisdoWidgetLiveActivityUpdater.updateExistingActivity(for: todo, categoryName: categoryName)
    }

    @MainActor
    static func toggleBlock(todoIDString: String, blockIDString: String) async throws {
        let context = try makeModelContext()
        let todos = try context.fetch(FetchDescriptor<Todo>())
        guard let todo = todos.todo(matching: todoIDString), todo.status == .open || todo.status == .inProgress else {
            throw LisdoWidgetIntentError.todoUnavailable
        }
        guard let blockID = UUID(uuidString: blockIDString),
              let block = todo.blocks?.first(where: { $0.id == blockID }) else {
            throw LisdoWidgetIntentError.blockUnavailable
        }

        block.checked.toggle()
        if todo.status == .open {
            todo.status = .inProgress
        }
        todo.updatedAt = Date()
        try context.save()

        let categoryName = try categoryName(for: todo.categoryId, in: context)
        await LisdoWidgetLiveActivityUpdater.updateExistingActivity(for: todo, categoryName: categoryName)
    }

    @MainActor
    static func completeTodo(idString: String) async throws {
        let context = try makeModelContext()
        let todos = try context.fetch(FetchDescriptor<Todo>())
        guard let todo = todos.todo(matching: idString), todo.status == .open || todo.status == .inProgress else {
            throw LisdoWidgetIntentError.todoUnavailable
        }

        todo.status = .completed
        todo.updatedAt = Date()
        todo.blocks?.forEach { block in
            block.checked = true
        }
        try context.save()

        let categoryName = try categoryName(for: todo.categoryId, in: context)
        await LisdoWidgetLiveActivityUpdater.endExistingActivity(for: todo, categoryName: categoryName)
    }

    private static func makeEntry(
        date: Date,
        categories: [LisdoCore.Category],
        drafts: [ProcessingDraft],
        captures: [CaptureItem],
        todos: [Todo]
    ) -> LisdoWidgetEntry {
        let categoryNames = Dictionary(
            categories.map { ($0.id, $0.name) },
            uniquingKeysWith: { existing, _ in existing }
        )
        let calendar = Calendar.current
        let plan = DailyExperienceState.makePlan(todos: todos, calendar: calendar, now: date)
        let widgetSnapshot = DailyExperienceState.widgetSnapshot(todos: todos, calendar: calendar, now: date)
        let activeTask = widgetSnapshot.activeTask.map { WidgetActiveTask(snapshot: $0, categoryNames: categoryNames) }
        let todayStart = calendar.startOfDay(for: date)
        let todaySnapshots = plan.sections
            .filter { $0.date == todayStart }
            .flatMap(\.todos)
            .sortedForTodayWidget()
            .map { WidgetTask(snapshot: $0, categoryNames: categoryNames) }

        let pendingCaptures = captures.filter(\.isWidgetPending)
        let failedCaptures = captures.filter(\.isWidgetFailed)
        let visibleCaptures = captures.filter(\.isWidgetVisibleCapture)
        let inboxItems = makeInboxItems(
            drafts: drafts,
            visibleCaptures: visibleCaptures,
            categoryNames: categoryNames
        )
        let focus = todaySnapshots.first
        let state: WidgetDataState = (focus == nil && drafts.isEmpty && visibleCaptures.isEmpty)
            ? .empty
            : .content

        return LisdoWidgetEntry(
            date: date,
            state: state,
            todayTodoCount: widgetSnapshot.todayTodoCount,
            draftCount: drafts.count,
            pendingCaptureCount: pendingCaptures.count,
            failedCaptureCount: failedCaptures.count,
            focus: focus,
            inboxItems: inboxItems,
            todayItems: Array(todaySnapshots),
            activeTask: activeTask
        )
    }

    private static func makeInboxItems(
        drafts: [ProcessingDraft],
        visibleCaptures: [CaptureItem],
        categoryNames: [String: String]
    ) -> [WidgetInboxItem] {
        let draftItems = drafts.prefix(3).map { draft in
            let categoryName = draft.recommendedCategoryId.flatMap { categoryNames[$0] } ?? "Inbox"
            return WidgetInboxItem(
                id: draft.id.uuidString,
                title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Review draft",
                metadata: "Draft ready · \(categoryName)",
                categoryId: draft.recommendedCategoryId,
                kind: .draft
            )
        }

        let captureItems = visibleCaptures.prefix(max(0, 3 - draftItems.count)).map { capture in
            WidgetInboxItem(
                id: capture.id.uuidString,
                title: capture.widgetTitle,
                metadata: capture.widgetStatus,
                categoryId: nil,
                kind: capture.isWidgetFailed ? .failed : .pending
            )
        }

        return Array(draftItems + captureItems)
    }

    private static func makeModelContext() throws -> ModelContext {
        ModelContext(try LisdoWidgetModelContainerFactory.makeContainer())
    }

    private static func categoryName(for id: String, in context: ModelContext) throws -> String {
        let categories = try context.fetch(FetchDescriptor<LisdoCore.Category>())
        return categories.first(where: { $0.id == id })?.name ?? "General"
    }
}

enum LisdoWidgetModelContainerFactory {
    static let cloudKitContainerIdentifier = "iCloud.com.yiwenwu.Lisdo"

    private static let schema = Schema([
        LisdoCore.Category.self,
        CaptureItem.self,
        ProcessingDraft.self,
        Todo.self,
        TodoBlock.self
    ])

    private static var cachedContainer: ModelContainer?

    static func makeContainer() throws -> ModelContainer {
        if let cachedContainer {
            return cachedContainer
        }

        let configuration = ModelConfiguration(
            "LisdoCloud",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        cachedContainer = container
        return container
    }
}

enum LisdoWidgetIntentError: Error {
    case todoUnavailable
    case blockUnavailable
}

private extension Array where Element == Todo {
    func todo(matching idString: String) -> Todo? {
        guard let id = UUID(uuidString: idString) else {
            return nil
        }

        return first(where: { $0.id == id })
    }
}

private extension WidgetTask {
    init(snapshot: DailyPlanTodoSnapshot, categoryNames: [String: String]) {
        self.init(
            id: snapshot.id.uuidString,
            title: snapshot.title,
            metadata: snapshot.widgetMetadata,
            categoryName: categoryNames[snapshot.categoryId] ?? "General",
            categoryId: snapshot.categoryId,
            status: snapshot.status
        )
    }

    init(activeTask: WidgetActiveTask) {
        self.init(
            id: activeTask.todoId,
            title: activeTask.title,
            metadata: "\(activeTask.categoryName) · Active",
            categoryName: activeTask.categoryName,
            categoryId: activeTask.categoryId,
            status: .inProgress
        )
    }
}

private extension WidgetActiveTask {
    init(snapshot: ActiveTaskSnapshot, categoryNames: [String: String]) {
        let progress = snapshot.totalStepCount > 0
            ? Double(snapshot.completedStepCount) / Double(snapshot.totalStepCount)
            : 0

        self.init(
            todoId: snapshot.todoId.uuidString,
            title: snapshot.title,
            categoryName: categoryNames[snapshot.categoryId] ?? "General",
            categoryId: snapshot.categoryId,
            currentStepBlockId: snapshot.currentStep?.blockId.uuidString,
            currentStep: snapshot.currentStep?.content ?? (snapshot.isComplete ? "All steps complete" : "No steps added"),
            nextStep: snapshot.nextStep?.content,
            progress: progress,
            progressLabel: snapshot.progressLabel
        )
    }
}

private extension Array where Element == DailyPlanTodoSnapshot {
    func sortedForTodayWidget() -> [DailyPlanTodoSnapshot] {
        sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status == .inProgress
            }

            if lhs.widgetSortDate != rhs.widgetSortDate {
                switch (lhs.widgetSortDate, rhs.widgetSortDate) {
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

private extension DailyPlanTodoSnapshot {
    var widgetSortDate: Date? {
        scheduledDate ?? dueDate
    }

    var widgetMetadata: String {
        if let scheduledDate {
            return Self.timeFormatter.string(from: scheduledDate)
        }

        if let dueDate {
            return Self.timeFormatter.string(from: dueDate)
        }

        if let dueDateText = dueDateText?.trimmingCharacters(in: .whitespacesAndNewlines), !dueDateText.isEmpty {
            return dueDateText
        }

        return status == .inProgress ? "Active" : "Saved"
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private extension CaptureItem {
    var isWidgetPending: Bool {
        switch status {
        case .rawCaptured, .pendingProcessing, .processing, .retryPending:
            true
        case .processedDraft, .approvedTodo, .failed:
            false
        }
    }

    var isWidgetFailed: Bool {
        status == .failed
    }

    var isWidgetVisibleCapture: Bool {
        isWidgetPending || isWidgetFailed
    }

    var widgetTitle: String {
        sourceText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? transcriptText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? sourceType.widgetTitle
    }

    var widgetStatus: String {
        switch status {
        case .rawCaptured:
            "Captured · \(preferredProviderMode.widgetStatusName)"
        case .pendingProcessing:
            preferredProviderMode.pendingWidgetStatus
        case .processing:
            "Processing · \(preferredProviderMode.widgetStatusName)"
        case .failed:
            "Failed · \(preferredProviderMode.widgetStatusName)"
        case .retryPending:
            "Retry · \(preferredProviderMode.widgetStatusName)"
        case .processedDraft:
            "Draft ready"
        case .approvedTodo:
            "Saved"
        }
    }
}

private extension ProviderMode {
    var widgetStatusName: String {
        switch self {
        case .openAICompatibleBYOK:
            "BYOK"
        case .lisdoManaged:
            "Lisdo"
        case .minimax:
            "MiniMax"
        case .anthropic:
            "Anthropic"
        case .gemini:
            "Gemini"
        case .openRouter:
            "OpenRouter"
        case .macOnlyCLI:
            "Mac CLI"
        case .ollama:
            "Ollama"
        case .lmStudio:
            "LM Studio"
        case .localModel:
            "Local model"
        }
    }

    var pendingWidgetStatus: String {
        switch self {
        case .macOnlyCLI:
            "Waiting for Mac"
        case .ollama, .lmStudio, .localModel:
            "Queued · \(widgetStatusName)"
        case .openAICompatibleBYOK, .lisdoManaged, .minimax, .anthropic, .gemini, .openRouter:
            "Queued · \(widgetStatusName)"
        }
    }
}

private extension CaptureSourceType {
    var widgetTitle: String {
        switch self {
        case .textPaste:
            "Text capture"
        case .clipboard:
            "Clipboard capture"
        case .macScreenRegion:
            "Mac screen capture"
        case .screenshotImport:
            "Screenshot capture"
        case .photoImport:
            "Photo capture"
        case .cameraImport:
            "Camera capture"
        case .shareExtension:
            "Shared capture"
        case .voiceNote:
            "Voice capture"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
