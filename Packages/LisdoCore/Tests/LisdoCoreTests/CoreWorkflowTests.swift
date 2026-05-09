import XCTest
@testable import LisdoCore

final class CoreWorkflowTests: XCTestCase {
    private let isoFormatter = ISO8601DateFormatter()

    func testCategoryFallbackUsesRecommendedCategoryWhenKnownAndConfident() {
        let work = Category(id: "work", name: "Work")
        let personal = Category(id: "personal", name: "Personal")
        let draft = ProcessingDraft(
            captureItemId: UUID(),
            recommendedCategoryId: "work",
            title: "Prepare report",
            confidence: 0.74
        )

        let result = CategoryRecommender.resolveCategory(for: draft, availableCategories: [personal, work], fallbackCategoryId: "personal")

        XCTAssertEqual(result.categoryId, "work")
        XCTAssertEqual(result.reason, .acceptedRecommendation)
    }

    func testCategoryFallbackUsesFallbackWhenRecommendationMissingUnknownOrLowConfidence() {
        let fallback = Category(id: "inbox", name: "Inbox")
        let work = Category(id: "work", name: "Work")

        let missing = ProcessingDraft(captureItemId: UUID(), recommendedCategoryId: nil, title: "Task", confidence: 0.9)
        XCTAssertEqual(CategoryRecommender.resolveCategory(for: missing, availableCategories: [fallback, work], fallbackCategoryId: "inbox").reason, .missingRecommendation)

        let unknown = ProcessingDraft(captureItemId: UUID(), recommendedCategoryId: "research", title: "Task", confidence: 0.9)
        XCTAssertEqual(CategoryRecommender.resolveCategory(for: unknown, availableCategories: [fallback, work], fallbackCategoryId: "inbox").reason, .unknownRecommendation)

        let lowConfidence = ProcessingDraft(captureItemId: UUID(), recommendedCategoryId: "work", title: "Task", confidence: 0.39)
        let result = CategoryRecommender.resolveCategory(for: lowConfidence, availableCategories: [fallback, work], fallbackCategoryId: "inbox", minimumConfidence: 0.4)
        XCTAssertEqual(result.categoryId, "inbox")
        XCTAssertEqual(result.reason, .lowConfidence)
    }

    func testDraftToTodoConversionRequiresExplicitApprovalAndPreservesBlockOrdering() throws {
        let captureId = UUID()
        let draft = ProcessingDraft(
            captureItemId: captureId,
            recommendedCategoryId: "work",
            title: "Prepare UCI Study Group questionnaire",
            summary: "Revise and send questionnaire.",
            blocks: [
                DraftBlock(type: .checkbox, content: "Second source order", checked: false, order: 1),
                DraftBlock(type: .note, content: "First source order", checked: false, order: 0)
            ],
            dueDateText: "tomorrow before 3 PM",
            priority: .medium,
            confidence: 0.82
        )

        XCTAssertThrowsError(try DraftApprovalConverter.convert(draft, categoryId: "work", approval: nil)) { error in
            XCTAssertEqual(error as? DraftApprovalError, .approvalRequired)
        }

        let approval = DraftApproval(approvedByUser: true, approvedAt: Date(timeIntervalSince1970: 10))
        let todo = try DraftApprovalConverter.convert(draft, categoryId: "work", approval: approval)

        XCTAssertEqual(todo.categoryId, "work")
        XCTAssertEqual(todo.title, draft.title)
        XCTAssertEqual(todo.summary, draft.summary)
        XCTAssertEqual(todo.priority, .medium)
        XCTAssertNil(todo.dueDate)
        XCTAssertEqual(todo.dueDateText, "tomorrow before 3 PM")
        let blocks = try XCTUnwrap(todo.blocks)
        XCTAssertEqual(blocks.map(\.content), ["First source order", "Second source order"])
        XCTAssertEqual(blocks.map(\.order), [0, 1])
        XCTAssertEqual(blocks.map(\.todoId), [todo.id, todo.id])
        XCTAssertEqual(blocks.map(\.todo?.id), [todo.id, todo.id])
    }

    func testDraftToTodoConversionCreatesOnlyApprovedSelectedReminderChildren() throws {
        let draft = ProcessingDraft(
            captureItemId: UUID(),
            recommendedCategoryId: "work",
            title: "Present final project",
            summary: "Prepare the final project presentation.",
            blocks: [
                DraftBlock(type: .checkbox, content: "Finish slide deck", checked: false, order: 0)
            ],
            suggestedReminders: [
                DraftReminderSuggestion(
                    title: "Update computer",
                    reminderDateText: "the day before",
                    reason: "Required system updates can take time",
                    defaultSelected: true,
                    order: 2
                ),
                DraftReminderSuggestion(
                    title: "Run tech check",
                    reminderDateText: "the day before",
                    reminderDate: isoDate("2026-05-08T09:00:00-04:00"),
                    reason: "Avoid presentation-day setup issues",
                    defaultSelected: true,
                    order: 1
                ),
                DraftReminderSuggestion(
                    title: "   ",
                    reminderDateText: "tomorrow",
                    reason: "Blank reminder titles must not become persisted reminders",
                    defaultSelected: true,
                    order: 0
                ),
                DraftReminderSuggestion(
                    title: "Message advisor",
                    reminderDateText: "two days before",
                    reason: "User did not approve this reminder by default",
                    defaultSelected: false,
                    order: 3
                )
            ]
        )

        XCTAssertThrowsError(try DraftApprovalConverter.convert(draft, categoryId: "work", approval: DraftApproval(approvedByUser: false))) { error in
            XCTAssertEqual(error as? DraftApprovalError, .approvalRequired)
        }

        let approvedAt = Date(timeIntervalSince1970: 25)
        let todo = try DraftApprovalConverter.convert(
            draft,
            categoryId: "work",
            approval: DraftApproval(approvedByUser: true, approvedAt: approvedAt)
        )

        let reminders = try XCTUnwrap(todo.reminders)
        XCTAssertEqual(reminders.map(\.title), ["Run tech check", "Update computer"])
        XCTAssertEqual(reminders.map(\.reminderDateText), ["the day before", "the day before"])
        XCTAssertEqual(reminders.map(\.reminderDate), [isoDate("2026-05-08T09:00:00-04:00"), nil])
        XCTAssertEqual(reminders.map(\.reason), ["Avoid presentation-day setup issues", "Required system updates can take time"])
        XCTAssertEqual(reminders.map(\.isCompleted), [false, false])
        XCTAssertEqual(reminders.map(\.order), [0, 1])
        XCTAssertEqual(reminders.map(\.todoId), [todo.id, todo.id])
        XCTAssertEqual(reminders.map(\.todo?.id), [todo.id, todo.id])
        XCTAssertEqual(reminders.map(\.createdAt), [approvedAt, approvedAt])
        XCTAssertEqual(reminders.map(\.updatedAt), [approvedAt, approvedAt])
    }

    func testDraftToTodoConversionPersistsCanonicalDueAndScheduledDates() throws {
        let dueDate = isoDate("2026-05-05T23:59:00-04:00")
        let scheduledDate = isoDate("2026-05-05T16:00:00-04:00")
        let referenceDate = isoDate("2026-05-04T15:30:00-04:00")
        let draft = ProcessingDraft(
            captureItemId: UUID(),
            recommendedCategoryId: "inbox",
            title: "Tacos & Tequila event",
            summary: "Axis 201 event happens tomorrow at 4 PM.",
            blocks: [
                DraftBlock(type: .note, content: "Event happens tomorrow at 4 PM", order: 0)
            ],
            dueDateText: "tomorrow at 4:00 PM",
            dueDate: dueDate,
            scheduledDate: scheduledDate,
            dateResolutionReferenceDate: referenceDate,
            priority: .medium
        )

        let todo = try DraftApprovalConverter.convert(
            draft,
            categoryId: "inbox",
            approval: DraftApproval(approvedByUser: true)
        )

        XCTAssertEqual(todo.dueDate, dueDate)
        XCTAssertEqual(todo.scheduledDate, scheduledDate)
        XCTAssertEqual(todo.dueDateText, "tomorrow at 4:00 PM")
    }

    func testCaptureStatusTransitionsAcceptValidFlowAndRejectInvalidTransitions() throws {
        let capture = CaptureItem(sourceType: .textPaste, sourceText: "Raw task", createdDevice: .mac, preferredProviderMode: .openAICompatibleBYOK)

        XCTAssertEqual(capture.status, .rawCaptured)
        try capture.transition(to: .pendingProcessing)
        try capture.transition(to: .processing)
        try capture.transition(to: .processedDraft)
        try capture.transition(to: .approvedTodo)

        XCTAssertThrowsError(try capture.transition(to: .processing)) { error in
            XCTAssertEqual(error as? CaptureStatusTransitionError, .invalidTransition(from: .approvedTodo, to: .processing))
        }
    }

    func testCaptureStatusFailureRetryFlow() throws {
        let capture = CaptureItem(sourceType: .voiceNote, transcriptText: "Call Yan", createdDevice: .iPhone, preferredProviderMode: .macOnlyCLI)

        try capture.transition(to: .pendingProcessing)
        try capture.transition(to: .processing)
        try capture.transition(to: .failed, error: "Provider timeout")

        XCTAssertEqual(capture.status, .failed)
        XCTAssertEqual(capture.processingError, "Provider timeout")

        try capture.transition(to: .retryPending)
        XCTAssertNil(capture.processingError)

        try capture.transition(to: .processing)
        XCTAssertEqual(capture.status, .processing)
    }

    private func isoDate(_ value: String) -> Date {
        guard let date = isoFormatter.date(from: value) else {
            XCTFail("Invalid ISO date fixture: \(value)")
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }
}
