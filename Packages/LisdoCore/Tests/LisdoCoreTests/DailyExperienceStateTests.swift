import XCTest
@testable import LisdoCore

final class DailyExperienceStateTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testPlanGroupsApprovedTodosByScheduledDateAndDueDate() throws {
        let now = date(year: 2026, month: 5, day: 2, hour: 12)
        let today = calendar.startOfDay(for: now)
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))

        let scheduled = makeTodo(title: "Prepare class notes", scheduledDate: date(year: 2026, month: 5, day: 2, hour: 16))
        let due = makeTodo(title: "Send questionnaire", dueDate: date(year: 2026, month: 5, day: 3, hour: 9))

        let plan = DailyExperienceState.makePlan(todos: [due, scheduled], calendar: calendar, now: now)

        XCTAssertEqual(plan.activeTodoCount, 2)
        XCTAssertEqual(plan.sections.map(\.kind), [
            .scheduledDate(today),
            .dueDate(tomorrow)
        ])
        XCTAssertEqual(plan.sections[0].todos.map(\.title), ["Prepare class notes"])
        XCTAssertEqual(plan.sections[1].todos.map(\.title), ["Send questionnaire"])
    }

    func testPlanUsesDueDateTextTodayAndTomorrowOnlyWhenNoConcreteDateExists() throws {
        let now = date(year: 2026, month: 5, day: 2, hour: 12)
        let today = calendar.startOfDay(for: now)
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))

        let todayText = makeTodo(title: "Update reading list", dueDateText: "today after lunch")
        let tomorrowText = makeTodo(title: "Confirm Zoom", dueDateText: "tomorrow before 3 PM")
        let concreteDateWins = makeTodo(
            title: "Concrete due date wins",
            dueDate: date(year: 2026, month: 5, day: 4, hour: 10),
            dueDateText: "today"
        )

        let plan = DailyExperienceState.makePlan(
            todos: [tomorrowText, concreteDateWins, todayText],
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(plan.sections.map(\.kind), [
            .naturalDueDateText(today),
            .naturalDueDateText(tomorrow),
            .dueDate(date(year: 2026, month: 5, day: 4))
        ])
        XCTAssertEqual(plan.sections[0].todos.first?.dueDateText, "today after lunch")
        XCTAssertEqual(plan.sections[1].todos.first?.dueDateText, "tomorrow before 3 PM")
        XCTAssertEqual(plan.sections[2].todos.first?.title, "Concrete due date wins")
    }

    func testPlanCreatesNoDateFallbackSection() {
        let now = date(year: 2026, month: 5, day: 2, hour: 12)
        let undated = makeTodo(title: "Sort captured notes")

        let plan = DailyExperienceState.makePlan(todos: [undated], calendar: calendar, now: now)

        XCTAssertEqual(plan.sections.map(\.kind), [.noDate])
        XCTAssertEqual(plan.sections.first?.title, "No date")
        XCTAssertEqual(plan.sections.first?.todos.map(\.title), ["Sort captured notes"])
    }

    func testPlanAndWidgetCountsExcludeCompletedAndArchivedTodos() {
        let now = date(year: 2026, month: 5, day: 2, hour: 12)
        let open = makeTodo(title: "Open today", dueDate: now, status: .open)
        let inProgress = makeTodo(title: "Active today", dueDate: now, status: .inProgress)
        let completed = makeTodo(title: "Completed today", dueDate: now, status: .completed)
        let archived = makeTodo(title: "Archived today", dueDate: now, status: .archived)

        let plan = DailyExperienceState.makePlan(
            todos: [open, inProgress, completed, archived],
            calendar: calendar,
            now: now
        )
        let widget = DailyExperienceState.widgetSnapshot(
            todos: [open, inProgress, completed, archived],
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(plan.activeTodoCount, 2)
        XCTAssertEqual(plan.sections.flatMap(\.todos).map(\.title), ["Open today", "Active today"])
        XCTAssertEqual(widget.todayTodoCount, 2)
        XCTAssertEqual(widget.activeTask?.title, "Active today")
    }

    func testActiveTaskPicksInProgressTodoAndDerivesCurrentNextAndProgress() throws {
        let open = makeTodo(
            title: "Open backup task",
            status: .open,
            blocks: [
                block("Open task step", checked: false, order: 0)
            ]
        )
        let active = makeTodo(
            title: "Prepare UCI class meeting",
            status: .inProgress,
            blocks: [
                block("Collect questions", checked: true, order: 0),
                block("Draft questionnaire", checked: false, order: 1),
                block("Send to Yan", checked: false, order: 2)
            ]
        )

        let snapshot = try XCTUnwrap(DailyExperienceState.activeTask(from: [open, active]))

        XCTAssertEqual(snapshot.todoId, active.id)
        XCTAssertEqual(snapshot.title, "Prepare UCI class meeting")
        XCTAssertEqual(snapshot.currentStep?.content, "Draft questionnaire")
        XCTAssertEqual(snapshot.nextStep?.content, "Send to Yan")
        XCTAssertEqual(snapshot.progressLabel, "Step 2 of 3")
        XCTAssertEqual(snapshot.completedStepCount, 1)
        XCTAssertEqual(snapshot.totalStepCount, 3)
        XCTAssertFalse(snapshot.isComplete)
    }

    func testActiveTaskProgressUsesOnlyCheckboxBlocksWithoutCreatingTodo() throws {
        let active = makeTodo(
            title: "Finish report",
            status: .inProgress,
            blocks: [
                block("Draft", type: .checkbox, checked: true, order: 0),
                block("Review context", type: .bullet, checked: true, order: 1),
                block("Ask Yan before sending", type: .note, checked: true, order: 2),
                block("Send", type: .checkbox, checked: false, order: 3)
            ]
        )

        let snapshot = try XCTUnwrap(DailyExperienceState.liveActivitySnapshot(from: [active]))

        XCTAssertEqual(snapshot.todoId, active.id)
        XCTAssertEqual(snapshot.currentStep?.content, "Send")
        XCTAssertNil(snapshot.nextStep)
        XCTAssertEqual(snapshot.progressLabel, "Step 2 of 2")
        XCTAssertEqual(snapshot.completedStepCount, 1)
        XCTAssertEqual(snapshot.totalStepCount, 2)
        XCTAssertFalse(snapshot.isComplete)
    }

    func testDailyExperienceHelpersAreDraftFirstByOnlyAcceptingTodos() {
        let draft = ProcessingDraft(
            captureItemId: UUID(),
            recommendedCategoryId: "work",
            title: "Unapproved draft",
            blocks: [DraftBlock(type: .checkbox, content: "Should stay draft", order: 0)]
        )
        let approvedTodo = Todo(
            categoryId: draft.recommendedCategoryId ?? "inbox",
            title: "User approved todo",
            blocks: [TodoBlock(todoId: UUID(), type: .checkbox, content: "Approved step", order: 0)]
        )

        let plan = DailyExperienceState.makePlan(todos: [approvedTodo], calendar: calendar, now: date(year: 2026, month: 5, day: 2))
        let active = DailyExperienceState.activeTask(from: [approvedTodo])

        XCTAssertEqual(plan.activeTodoCount, 1)
        XCTAssertNil(active)
        XCTAssertEqual(draft.title, "Unapproved draft")
    }

    private func makeTodo(
        title: String,
        dueDate: Date? = nil,
        dueDateText: String? = nil,
        scheduledDate: Date? = nil,
        status: TodoStatus = .open,
        blocks: [TodoBlock] = []
    ) -> Todo {
        Todo(
            categoryId: "work",
            title: title,
            status: status,
            dueDate: dueDate,
            dueDateText: dueDateText,
            scheduledDate: scheduledDate,
            blocks: blocks
        )
    }

    private func block(
        _ content: String,
        type: TodoBlockType = .checkbox,
        checked: Bool,
        order: Int
    ) -> TodoBlock {
        TodoBlock(todoId: UUID(), type: type, content: content, checked: checked, order: order)
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour).date!
    }
}
