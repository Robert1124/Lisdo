import XCTest
@testable import LisdoCore

final class AdvancedCoreHelpersTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testAdvancedSearchFiltersCapturesDraftsAndTodosAcrossTextStatusAndCategory() {
        let matchingCapture = CaptureItem(
            sourceType: .voiceNote,
            transcriptText: "Confirm Zoom recording settings with Yan",
            createdDevice: .iPhone,
            status: .failed,
            preferredProviderMode: .gemini
        )
        let hiddenCapture = CaptureItem(
            sourceType: .textPaste,
            sourceText: "Buy groceries",
            createdDevice: .mac,
            status: .processedDraft,
            preferredProviderMode: .openAICompatibleBYOK
        )
        let matchingDraft = ProcessingDraft(
            captureItemId: matchingCapture.id,
            recommendedCategoryId: "work",
            title: "Confirm Zoom settings",
            summary: "Ask Yan to verify recording.",
            blocks: [DraftBlock(type: .checkbox, content: "Confirm recording", order: 0)],
            needsClarification: true
        )
        let hiddenDraft = ProcessingDraft(captureItemId: hiddenCapture.id, recommendedCategoryId: "personal", title: "Buy milk")
        let matchingTodo = Todo(
            categoryId: "work",
            title: "Send Zoom notes",
            summary: "Follow up with Yan",
            status: .open,
            priority: .high,
            blocks: [TodoBlock(todoId: UUID(), type: .checkbox, content: "Send recording link", order: 0)]
        )
        let hiddenTodo = Todo(categoryId: "personal", title: "Groceries", status: .open, priority: .low)

        let query = AdvancedSearchQuery(
            text: "zoom yan",
            captureStatuses: [.failed],
            providerModes: [.gemini],
            categoryIds: ["work"],
            draftNeedsClarification: true,
            todoStatuses: [.open],
            priorities: [.high]
        )

        let result = LisdoAdvancedSearch.filter(
            captures: [hiddenCapture, matchingCapture],
            drafts: [hiddenDraft, matchingDraft],
            todos: [hiddenTodo, matchingTodo],
            query: query
        )

        XCTAssertEqual(result.captures.map(\.id), [matchingCapture.id])
        XCTAssertEqual(result.drafts.map(\.id), [matchingDraft.id])
        XCTAssertEqual(result.todos.map(\.id), [matchingTodo.id])
    }

    func testBatchHelpersSelectPendingFailedRetryCapturesAndArchiveCompletedTodos() throws {
        let pending = makeCapture(status: .pendingProcessing)
        let retry = makeCapture(status: .retryPending)
        let failed = makeCapture(status: .failed)
        let processing = makeCapture(status: .processing)

        XCTAssertEqual(CaptureBatchSelector.processablePendingCaptures(from: [processing, retry, pending]).map(\.id), [retry.id, pending.id])
        XCTAssertEqual(CaptureBatchSelector.failedCaptures(from: [pending, failed]).map(\.id), [failed.id])

        let retried = try CaptureBatchActions.queueFailedCapturesForRetry([failed, pending])
        XCTAssertEqual(retried.map(\.id), [failed.id])
        XCTAssertEqual(failed.status, .retryPending)
        XCTAssertEqual(pending.status, .pendingProcessing)

        let oldCompleted = Todo(
            categoryId: "work",
            title: "Old completed",
            status: .completed,
            updatedAt: date(year: 2026, month: 4, day: 20)
        )
        let newCompleted = Todo(
            categoryId: "work",
            title: "New completed",
            status: .completed,
            updatedAt: date(year: 2026, month: 5, day: 2)
        )
        let open = Todo(categoryId: "work", title: "Open", status: .open)

        let archived = CaptureBatchActions.archiveCompletedTodos([oldCompleted, newCompleted, open], completedBefore: date(year: 2026, month: 5, day: 1))

        XCTAssertEqual(archived.map(\.id), [oldCompleted.id])
        XCTAssertEqual(oldCompleted.status, .archived)
        XCTAssertEqual(newCompleted.status, .completed)
        XCTAssertEqual(open.status, .open)
    }

    func testTrashPolicySoftDeletesTodosAndPurgesAfterThirtyDays() {
        let now = date(year: 2026, month: 5, day: 10)
        let deletedAt = date(year: 2026, month: 4, day: 5)
        let expired = Todo(categoryId: "work", title: "Expired trash", status: .trashed, updatedAt: deletedAt)
        let recent = Todo(categoryId: "work", title: "Recent trash", status: .trashed, updatedAt: date(year: 2026, month: 4, day: 20))
        let active = Todo(categoryId: "work", title: "Active", status: .open)

        let trashed = TodoTrashPolicy.moveToTrash([active], trashedAt: now)

        XCTAssertEqual(trashed.map(\.id), [active.id])
        XCTAssertEqual(active.status, .trashed)
        XCTAssertEqual(active.updatedAt, now)
        XCTAssertEqual(TodoTrashPolicy.expiredTrashedTodos([expired, recent, active], now: now).map(\.id), [expired.id])
    }

    func testCategorySmartListsExposeArchiveAndTrashInsteadOfCapturedWithoutDraft() {
        let smartLists = LisdoCategorySmartListKind.defaultKinds

        XCTAssertEqual(smartLists.map(\.title), ["Today", "AI Drafts", "Archive", "Trash", "Needs attention"])
        XCTAssertFalse(smartLists.map(\.title).contains("Captured without draft"))
    }

    func testHostedProviderQueuePolicyIncludesIPhonePendingMediaWithoutOCRText() {
        let screenshot = CaptureItem(
            sourceType: .screenshotImport,
            sourceImageAssetId: "shared-screenshot.png",
            createdDevice: .iPhone,
            status: .pendingProcessing,
            preferredProviderMode: .minimax
        )
        let macCLI = CaptureItem(
            sourceType: .screenshotImport,
            sourceImageAssetId: "mac-cli.png",
            createdDevice: .iPhone,
            status: .pendingProcessing,
            preferredProviderMode: .macOnlyCLI
        )
        let macHosted = CaptureItem(
            sourceType: .screenshotImport,
            sourceImageAssetId: "mac-hosted.png",
            createdDevice: .mac,
            status: .pendingProcessing,
            preferredProviderMode: .openAICompatibleBYOK
        )

        XCTAssertTrue(HostedProviderQueuePolicy.isIPhoneHostedPendingCandidate(screenshot))
        XCTAssertFalse(HostedProviderQueuePolicy.isIPhoneHostedPendingCandidate(macCLI))
        XCTAssertFalse(HostedProviderQueuePolicy.isIPhoneHostedPendingCandidate(macHosted))
    }

    func testHostedProviderQueuePolicyDoesNotRetryProcessingOrFailedCapturesAutomatically() {
        let processing = CaptureItem(
            sourceType: .textPaste,
            sourceText: "Task",
            createdDevice: .iPhone,
            status: .processing,
            preferredProviderMode: .openAICompatibleBYOK
        )
        let failed = CaptureItem(
            sourceType: .textPaste,
            sourceText: "Task",
            createdDevice: .iPhone,
            status: .failed,
            preferredProviderMode: .openAICompatibleBYOK
        )
        let retry = CaptureItem(
            sourceType: .textPaste,
            sourceText: "Task",
            createdDevice: .iPhone,
            status: .retryPending,
            preferredProviderMode: .openAICompatibleBYOK
        )

        XCTAssertFalse(HostedProviderQueuePolicy.isIPhoneHostedPendingCandidate(processing))
        XCTAssertFalse(HostedProviderQueuePolicy.isIPhoneHostedPendingCandidate(failed))
        XCTAssertTrue(HostedProviderQueuePolicy.isIPhoneHostedPendingCandidate(retry))
    }

    func testSavedTodoCompletionToggleUpdatesStatusTimestampAndBlocks() {
        let toggleDate = date(year: 2026, month: 5, day: 4, hour: 9)
        let firstBlock = TodoBlock(todoId: UUID(), type: .checkbox, content: "First", checked: false, order: 0)
        let secondBlock = TodoBlock(todoId: UUID(), type: .checkbox, content: "Second", checked: false, order: 1)
        let open = Todo(
            categoryId: "work",
            title: "Open todo",
            status: .open,
            updatedAt: date(year: 2026, month: 5, day: 1),
            blocks: [firstBlock, secondBlock]
        )

        CaptureBatchActions.toggleSavedTodoCompletion(open, updatedAt: toggleDate)

        XCTAssertEqual(open.status, .completed)
        XCTAssertEqual(open.updatedAt, toggleDate)
        XCTAssertEqual(open.blocks?.map(\.checked), [true, true])

        let reopenDate = date(year: 2026, month: 5, day: 4, hour: 10)
        CaptureBatchActions.toggleSavedTodoCompletion(open, updatedAt: reopenDate)

        XCTAssertEqual(open.status, .open)
        XCTAssertEqual(open.updatedAt, reopenDate)
        XCTAssertEqual(open.blocks?.map(\.checked), [true, true])
    }

    func testDeletionPolicyAllowsDraftAndCaptureCleanupWithoutTouchingApprovedTodos() {
        let readyCapture = makeCapture(status: .processedDraft)
        let approvedCapture = makeCapture(status: .approvedTodo)
        let pendingCapture = makeCapture(status: .pendingProcessing)
        let failedCapture = makeCapture(status: .failed)
        let retryCapture = makeCapture(status: .retryPending)
        let readyDraft = ProcessingDraft(captureItemId: readyCapture.id, title: "Ready draft")
        let approvedDraft = ProcessingDraft(captureItemId: approvedCapture.id, title: "Saved draft")

        XCTAssertEqual(
            CaptureDeletionPolicy.captureIdsToDelete(whenDeleting: readyDraft, captures: [readyCapture, approvedCapture]),
            [readyCapture.id]
        )
        XCTAssertEqual(
            CaptureDeletionPolicy.captureIdsToDelete(whenDeleting: approvedDraft, captures: [readyCapture, approvedCapture]),
            []
        )
        XCTAssertTrue(CaptureDeletionPolicy.canDeleteCapture(pendingCapture))
        XCTAssertTrue(CaptureDeletionPolicy.canDeleteCapture(failedCapture))
        XCTAssertTrue(CaptureDeletionPolicy.canDeleteCapture(retryCapture))
        XCTAssertFalse(CaptureDeletionPolicy.canDeleteCapture(approvedCapture))
    }

    func testAdvancedPlanGroupsInternalTodosByOverdueTodayUpcomingNoDateAndSummaries() throws {
        let now = date(year: 2026, month: 5, day: 3, hour: 10)
        let overdue = Todo(categoryId: "work", title: "Overdue", status: .open, dueDate: date(year: 2026, month: 5, day: 2), priority: .high)
        let today = Todo(categoryId: "research", title: "Today", status: .inProgress, scheduledDate: date(year: 2026, month: 5, day: 3, hour: 15), priority: .medium)
        let upcoming = Todo(categoryId: "work", title: "Upcoming", status: .open, dueDate: date(year: 2026, month: 5, day: 5), priority: .low)
        let noDate = Todo(categoryId: "inbox", title: "No date", status: .open)
        let completed = Todo(categoryId: "work", title: "Completed", status: .completed, dueDate: date(year: 2026, month: 5, day: 1), priority: .high)
        let categories = [
            Category(id: "work", name: "Work"),
            Category(id: "research", name: "Research"),
            Category(id: "inbox", name: "Inbox")
        ]

        let snapshot = AdvancedPlanBuilder.makeSnapshot(
            todos: [upcoming, completed, noDate, today, overdue],
            categories: categories,
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(snapshot.activeTodoCount, 4)
        XCTAssertEqual(snapshot.buckets.map(\.kind), [.overdue, .today, .upcoming, .noDate])
        XCTAssertEqual(snapshot.buckets[0].todos.map(\.title), ["Overdue"])
        XCTAssertEqual(snapshot.buckets[1].todos.map(\.title), ["Today"])
        XCTAssertEqual(snapshot.buckets[2].todos.map(\.title), ["Upcoming"])
        XCTAssertEqual(snapshot.buckets[3].todos.map(\.title), ["No date"])
        XCTAssertEqual(snapshot.prioritySummary.high, 1)
        XCTAssertEqual(snapshot.prioritySummary.medium, 1)
        XCTAssertEqual(snapshot.prioritySummary.low, 1)
        XCTAssertEqual(snapshot.prioritySummary.none, 1)
        XCTAssertEqual(snapshot.categorySummaries.map(\.categoryName), ["Inbox", "Research", "Work"])
        XCTAssertEqual(snapshot.categorySummaries.map(\.count), [1, 1, 2])
    }

    func testAdvancedPlanUsesNaturalTodayAndTomorrowDueDateTextAsDatedTodos() throws {
        let now = date(year: 2026, month: 5, day: 5, hour: 10)
        let todayText = Todo(categoryId: "inbox", title: "Today text", status: .open, dueDateText: "today")
        let tomorrowText = Todo(categoryId: "inbox", title: "Tomorrow text", status: .open, dueDateText: "tomorrow morning")
        let noDate = Todo(categoryId: "inbox", title: "No date", status: .open)

        let snapshot = AdvancedPlanBuilder.makeSnapshot(
            todos: [noDate, tomorrowText, todayText],
            categories: [Category(id: "inbox", name: "Inbox")],
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(snapshot.buckets.map(\.kind), [.today, .upcoming, .noDate])
        XCTAssertEqual(snapshot.buckets[0].todos.map(\.title), ["Today text"])
        XCTAssertEqual(snapshot.buckets[1].todos.map(\.title), ["Tomorrow text"])
        XCTAssertEqual(snapshot.buckets[2].todos.map(\.title), ["No date"])
    }

    func testAdvancedPlanHandlesDuplicateCategoryIdsWithoutCrashing() throws {
        let todo = Todo(categoryId: "inbox", title: "Keep Plan open", status: .open)
        let categories = [
            Category(id: "inbox", name: "Inbox"),
            Category(id: "inbox", name: "Inbox copy")
        ]

        let snapshot = AdvancedPlanBuilder.makeSnapshot(
            todos: [todo],
            categories: categories,
            calendar: calendar,
            now: date(year: 2026, month: 5, day: 5)
        )

        XCTAssertEqual(snapshot.categorySummaries.map(\.categoryId), ["inbox"])
        XCTAssertEqual(snapshot.categorySummaries.map(\.count), [1])
    }

    private func makeCapture(status: CaptureStatus) -> CaptureItem {
        CaptureItem(
            sourceType: .textPaste,
            sourceText: "Task",
            createdDevice: .mac,
            status: status,
            preferredProviderMode: .openAICompatibleBYOK
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour).date!
    }
}
