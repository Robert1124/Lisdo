import XCTest
@testable import LisdoCore

final class DraftParserTests: XCTestCase {
    private let isoFormatter = ISO8601DateFormatter()

    func testParsesValidStrictDraftJSON() throws {
        let json = """
        {
          "recommendedCategoryId": "work",
          "confidence": 0.82,
          "title": "Prepare UCI Study Group questionnaire",
          "summary": "Revise the questionnaire, send it to Yan, and confirm Zoom recording settings.",
          "blocks": [
            { "type": "checkbox", "content": "Revise the questionnaire", "checked": false },
            { "type": "bullet", "content": "Confirm Zoom recording settings" }
          ],
          "dueDateText": "tomorrow before 3 PM",
          "priority": "medium",
          "needsClarification": false,
          "questionsForUser": []
        }
        """

        let draft = try TaskDraftParser.parse(json, captureItemId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, generatedByProvider: "test-provider")

        XCTAssertEqual(draft.recommendedCategoryId, "work")
        XCTAssertEqual(draft.confidence, 0.82)
        XCTAssertEqual(draft.title, "Prepare UCI Study Group questionnaire")
        XCTAssertEqual(draft.summary, "Revise the questionnaire, send it to Yan, and confirm Zoom recording settings.")
        XCTAssertEqual(draft.blocks.count, 2)
        XCTAssertEqual(draft.blocks[0].type, .checkbox)
        XCTAssertFalse(draft.blocks[0].checked)
        XCTAssertEqual(draft.blocks[0].order, 0)
        XCTAssertEqual(draft.blocks[1].type, .bullet)
        XCTAssertEqual(draft.blocks[1].order, 1)
        XCTAssertEqual(draft.dueDateText, "tomorrow before 3 PM")
        XCTAssertEqual(draft.priority, .medium)
        XCTAssertFalse(draft.needsClarification)
        XCTAssertEqual(draft.generatedByProvider, "test-provider")
    }

    func testParserDoesNotTrustProviderCheckedStateBeforeUserReview() throws {
        let json = """
        {
          "recommendedCategoryId": "work",
          "confidence": 0.82,
          "title": "Prepare UCI Study Group questionnaire",
          "summary": "Revise the questionnaire and keep the source note.",
          "blocks": [
            { "type": "checkbox", "content": "Revise the questionnaire", "checked": true },
            { "type": "note", "content": "Source note for review", "checked": true }
          ],
          "needsClarification": false,
          "questionsForUser": []
        }
        """

        let draft = try TaskDraftParser.parse(json, captureItemId: UUID(), generatedByProvider: "test-provider")

        XCTAssertEqual(draft.blocks.map(\.checked), [false, false])
    }

    func testParsesCanonicalISODatesForDueAndScheduledDates() throws {
        let json = """
        {
          "recommendedCategoryId": "inbox",
          "confidence": 0.88,
          "title": "Tacos & Tequila event",
          "summary": "Axis 201 event happens tomorrow at 4 PM.",
          "blocks": [
            { "type": "note", "content": "Event happens tomorrow at 4 PM", "checked": false }
          ],
          "dueDateText": "tomorrow at 4:00 PM",
          "dueDateISO": null,
          "scheduledDateISO": "2026-05-05T16:00:00-04:00",
          "dateResolutionReferenceISO": "2026-05-04T15:30:00-04:00",
          "priority": "medium",
          "needsClarification": false,
          "questionsForUser": []
        }
        """

        let draft = try TaskDraftParser.parse(json, captureItemId: UUID(), generatedByProvider: "test")

        XCTAssertNil(draft.dueDate)
        XCTAssertEqual(draft.dueDateText, "tomorrow at 4:00 PM")
        XCTAssertEqual(draft.scheduledDate, isoDate("2026-05-05T16:00:00-04:00"))
        XCTAssertEqual(draft.dateResolutionReferenceDate, isoDate("2026-05-04T15:30:00-04:00"))
    }

    func testParsesSuggestedRemindersAttachedToDraft() throws {
        let json = """
        {
          "recommendedCategoryId": "work",
          "confidence": 0.9,
          "title": "Present final project",
          "summary": "Prepare for the final project presentation.",
          "blocks": [
            { "type": "checkbox", "content": "Finish slide deck", "checked": false }
          ],
          "suggestedReminders": [
            {
              "title": "Run tech check",
              "reminderDateText": "the day before",
              "reminderDateISO": "2026-05-08T09:00:00-04:00",
              "reason": "Avoid presentation-day setup issues",
              "defaultSelected": true,
              "order": 2
            },
            {
              "title": "Update computer",
              "reminderDateText": "the day before",
              "reason": "Required system updates can take time",
              "defaultSelected": false,
              "order": 1
            }
          ],
          "dueDateText": "Friday at 10 AM",
          "priority": "high",
          "needsClarification": false,
          "questionsForUser": []
        }
        """

        let draft = try TaskDraftParser.parse(json, captureItemId: UUID(), generatedByProvider: "test")

        XCTAssertEqual(draft.suggestedReminders.count, 2)
        XCTAssertEqual(draft.suggestedReminders[0].title, "Run tech check")
        XCTAssertEqual(draft.suggestedReminders[0].reminderDateText, "the day before")
        XCTAssertEqual(draft.suggestedReminders[0].reminderDate, isoDate("2026-05-08T09:00:00-04:00"))
        XCTAssertEqual(draft.suggestedReminders[0].reason, "Avoid presentation-day setup issues")
        XCTAssertTrue(draft.suggestedReminders[0].defaultSelected)
        XCTAssertEqual(draft.suggestedReminders[0].order, 2)
        XCTAssertEqual(draft.suggestedReminders[1].title, "Update computer")
        XCTAssertFalse(draft.suggestedReminders[1].defaultSelected)
        XCTAssertEqual(draft.suggestedReminders[1].order, 1)
    }

    func testParsesOlderDraftJSONWithoutSuggestedRemindersAsEmptyArray() throws {
        let json = """
        {
          "recommendedCategoryId": "work",
          "confidence": 0.82,
          "title": "Prepare UCI Study Group questionnaire",
          "summary": "Revise the questionnaire.",
          "blocks": [
            { "type": "checkbox", "content": "Revise the questionnaire", "checked": false }
          ],
          "dueDateText": "tomorrow before 3 PM",
          "priority": "medium",
          "needsClarification": false,
          "questionsForUser": []
        }
        """

        let draft = try TaskDraftParser.parse(json, captureItemId: UUID(), generatedByProvider: "test")

        XCTAssertTrue(draft.suggestedReminders.isEmpty)
    }

    func testRejectsFreeFormMarkdownAsInvalidJSON() {
        XCTAssertThrowsError(try TaskDraftParser.parse("- [ ] Revise the questionnaire", captureItemId: UUID(), generatedByProvider: "test")) { error in
            XCTAssertEqual(error as? DraftParsingError, .invalidJSON)
        }
    }

    func testStrictParserRejectsLeadingThinkBlockAsInvalidJSON() {
        let json = """
        <think>
        The user wants a work task. I should classify this as Work and return JSON.
        </think>
        {
          "recommendedCategoryId": "work",
          "confidence": 0.91,
          "title": "Send questionnaire to Yan",
          "blocks": [
            { "type": "checkbox", "content": "Revise the questionnaire", "checked": false }
          ],
          "needsClarification": false,
          "questionsForUser": []
        }
        """

        XCTAssertThrowsError(try TaskDraftParser.parse(json, captureItemId: UUID(), generatedByProvider: "minimax")) { error in
            XCTAssertEqual(error as? DraftParsingError, .invalidJSON)
        }
    }

    func testRejectsMarkdownWrappedJSONAsInvalidJSON() {
        let markdown = """
        ```json
        {
          "title": "Wrapped JSON",
          "blocks": [
            { "type": "checkbox", "content": "Do the thing", "checked": false }
          ],
          "needsClarification": false,
          "questionsForUser": []
        }
        ```
        """

        XCTAssertThrowsError(try TaskDraftParser.parse(markdown, captureItemId: UUID(), generatedByProvider: "test")) { error in
            XCTAssertEqual(error as? DraftParsingError, .invalidJSON)
        }
    }

    func testParsesClarificationOnlyDraftWithoutTitleOrBlocks() throws {
        let json = """
        {
          "needsClarification": true,
          "questionsForUser": [
            "Which assignment is this for?",
            "When is it due?"
          ]
        }
        """

        let draft = try TaskDraftParser.parse(json, captureItemId: UUID(), generatedByProvider: "test")

        XCTAssertTrue(draft.needsClarification)
        XCTAssertEqual(draft.questionsForUser, [
            "Which assignment is this for?",
            "When is it due?"
        ])
        XCTAssertEqual(draft.title, "Clarification needed")
        XCTAssertNil(draft.recommendedCategoryId)
        XCTAssertTrue(draft.blocks.isEmpty)
    }

    func testRejectsMissingRequiredTitle() {
        let json = """
        {
          "recommendedCategoryId": "work",
          "confidence": 0.8,
          "summary": "Missing title",
          "blocks": [
            { "type": "checkbox", "content": "Do the thing", "checked": false }
          ],
          "needsClarification": false,
          "questionsForUser": []
        }
        """

        XCTAssertThrowsError(try TaskDraftParser.parse(json, captureItemId: UUID(), generatedByProvider: "test")) { error in
            XCTAssertEqual(error as? DraftParsingError, .missingRequiredField("title"))
        }
    }

    func testPreservesClarificationQuestions() throws {
        let json = """
        {
          "recommendedCategoryId": null,
          "confidence": 0.2,
          "title": "Clarify meeting details",
          "summary": null,
          "blocks": [
            { "type": "note", "content": "Need user confirmation before saving." }
          ],
          "dueDateText": null,
          "priority": "low",
          "needsClarification": true,
          "questionsForUser": [
            "What time is tomorrow's meeting?",
            "Which category should this go in?"
          ]
        }
        """

        let draft = try TaskDraftParser.parse(json, captureItemId: UUID(), generatedByProvider: "test")

        XCTAssertTrue(draft.needsClarification)
        XCTAssertEqual(draft.questionsForUser, [
            "What time is tomorrow's meeting?",
            "Which category should this go in?"
        ])
    }

    func testRejectsInvalidBlockContentAndType() {
        let emptyContent = """
        {
          "title": "Bad block",
          "blocks": [
            { "type": "checkbox", "content": "   ", "checked": false }
          ],
          "needsClarification": false,
          "questionsForUser": []
        }
        """
        XCTAssertThrowsError(try TaskDraftParser.parse(emptyContent, captureItemId: UUID(), generatedByProvider: "test")) { error in
            XCTAssertEqual(error as? DraftParsingError, .invalidBlockContent(index: 0))
        }

        let invalidType = """
        {
          "title": "Bad block",
          "blocks": [
            { "type": "heading", "content": "Unsupported block" }
          ],
          "needsClarification": false,
          "questionsForUser": []
        }
        """
        XCTAssertThrowsError(try TaskDraftParser.parse(invalidType, captureItemId: UUID(), generatedByProvider: "test")) { error in
            XCTAssertEqual(error as? DraftParsingError, .invalidBlockType(index: 0, type: "heading"))
        }
    }

    private func isoDate(_ value: String) -> Date {
        isoFormatter.date(from: value)!
    }
}

final class MiniMaxDraftParserTests: XCTestCase {
    func testMiniMaxParserExtractsJSONAfterThinkBlock() throws {
        let content = """
        <think>
        The user wants a work task. I should classify this as Work and return JSON.
        </think>
        {
          "recommendedCategoryId": "work",
          "confidence": 0.91,
          "title": "Send questionnaire to Yan",
          "summary": "Revise the questionnaire and send it to Yan for review.",
          "blocks": [
            { "type": "checkbox", "content": "Revise the questionnaire", "checked": false },
            { "type": "checkbox", "content": "Send the questionnaire to Yan", "checked": false }
          ],
          "needsClarification": false,
          "questionsForUser": []
        }
        """

        let draft = try MiniMaxDraftParser.parse(content, captureItemId: UUID(), generatedByProvider: "minimax")

        XCTAssertEqual(draft.recommendedCategoryId, "work")
        XCTAssertEqual(draft.title, "Send questionnaire to Yan")
        XCTAssertEqual(draft.blocks.count, 2)
        XCTAssertFalse(draft.needsClarification)
    }

    func testMiniMaxParserExtractsJSONFromStrayReasoningText() throws {
        let content = """
        I'll analyze this task. The user wants to prepare a questionnaire for a UCI study group meeting.

        Based on the content, this seems like a work-related task.

        {"recommendedCategoryId":"work","confidence":0.88,"title":"Prepare UCI questionnaire","summary":"Complete and send the questionnaire.","blocks":[{"type":"checkbox","content":"Complete the questionnaire","checked":false}],"needsClarification":false,"questionsForUser":[]}
        """

        let draft = try MiniMaxDraftParser.parse(content, captureItemId: UUID(), generatedByProvider: "minimax")

        XCTAssertEqual(draft.title, "Prepare UCI questionnaire")
        XCTAssertEqual(draft.blocks.count, 1)
        XCTAssertEqual(draft.blocks[0].content, "Complete the questionnaire")
    }

    func testMiniMaxParserOutputIsProcessingDraftRequiringExplicitApproval() throws {
        let content = """
        {"recommendedCategoryId":"work","confidence":0.9,"title":"Complete UCI questionnaire","summary":"Do the thing.","blocks":[{"type":"checkbox","content":"Do the thing","checked":false}],"needsClarification":false,"questionsForUser":[]}
        """

        let captureId = UUID()
        let draft = try MiniMaxDraftParser.parse(content, captureItemId: captureId, generatedByProvider: "minimax")

        XCTAssertEqual(draft.captureItemId, captureId)
        XCTAssertEqual(draft.generatedByProvider, "minimax")

        XCTAssertThrowsError(try DraftApprovalConverter.convert(draft, categoryId: "work", approval: nil)) { error in
            XCTAssertEqual(error as? DraftApprovalError, .approvalRequired)
        }

        XCTAssertThrowsError(
            try DraftApprovalConverter.convert(draft, categoryId: "work", approval: DraftApproval(approvedByUser: false))
        ) { error in
            XCTAssertEqual(error as? DraftApprovalError, .approvalRequired)
        }

        let approval = DraftApproval(approvedByUser: true, approvedAt: Date())
        let todo = try DraftApprovalConverter.convert(draft, categoryId: "work", approval: approval)
        XCTAssertEqual(todo.title, "Complete UCI questionnaire")
        XCTAssertEqual(todo.categoryId, "work")
    }

    func testMiniMaxParserPreservesValidationErrors() {
        let contentWithInvalidBlock = """
        <think>Reasoning...</think>
        {"title":"Bad","blocks":[{"type":"heading","content":"Unsupported"}],"needsClarification":false,"questionsForUser":[]}
        """
        XCTAssertThrowsError(
            try MiniMaxDraftParser.parse(contentWithInvalidBlock, captureItemId: UUID(), generatedByProvider: "minimax")
        ) { error in
            XCTAssertEqual(error as? DraftParsingError, .invalidBlockType(index: 0, type: "heading"))
        }

        let contentMissingTitle = """
        I'll analyze this.
        {"confidence":0.5,"blocks":[{"type":"checkbox","content":"Do the thing","checked":false}],"needsClarification":false,"questionsForUser":[]}
        """
        XCTAssertThrowsError(
            try MiniMaxDraftParser.parse(contentMissingTitle, captureItemId: UUID(), generatedByProvider: "minimax")
        ) { error in
            XCTAssertEqual(error as? DraftParsingError, .missingRequiredField("title"))
        }
    }

    func testMiniMaxParserHandlesStrayQuotedPhraseBeforeJSON() throws {
        // Odd number of quotes before the first { makes the broken scanner enter inString=true,
        // causing it to miss the opening brace entirely and fall back to the raw content.
        let content = """
        The note says "buy milk". Also check "groceries" and "study for exam
        {"recommendedCategoryId":"work","confidence":0.85,"title":"Study for exam","summary":"Prepare.","blocks":[{"type":"checkbox","content":"Study chapter 1","checked":false}],"needsClarification":false,"questionsForUser":[]}
        """

        let draft = try MiniMaxDraftParser.parse(content, captureItemId: UUID(), generatedByProvider: "minimax")
        XCTAssertEqual(draft.title, "Study for exam")
        XCTAssertEqual(draft.blocks.count, 1)
        XCTAssertEqual(draft.blocks[0].content, "Study chapter 1")
    }

    func testMiniMaxParserHandlesStrayClosingBraceBeforeJSON() throws {
        let content = """
        Reasoning note with a stray } before the final JSON.
        {
          "recommendedCategoryId": "work",
          "confidence": 0.87,
          "title": "Review practice problems",
          "blocks": [
            { "type": "checkbox", "content": "Open the practice problem sheet", "checked": false }
          ],
          "needsClarification": false,
          "questionsForUser": []
        }
        """

        let draft = try MiniMaxDraftParser.parse(content, captureItemId: UUID(), generatedByProvider: "minimax")

        XCTAssertEqual(draft.title, "Review practice problems")
    }

    func testMiniMaxParserExtractsJSONAfterThinkBlockWithProse() throws {
        let content = """
        <think>
        Reasoning about the task.
        </think>
        Here is the JSON:
        {
          "recommendedCategoryId": "work",
          "confidence": 0.85,
          "title": "Buy groceries",
          "blocks": [
            { "type": "checkbox", "content": "Go to the store", "checked": false }
          ],
          "needsClarification": false,
          "questionsForUser": []
        }
        """

        let draft = try MiniMaxDraftParser.parse(content, captureItemId: UUID(), generatedByProvider: "minimax")
        XCTAssertEqual(draft.title, "Buy groceries")
        XCTAssertEqual(draft.blocks.count, 1)
        XCTAssertEqual(draft.blocks[0].content, "Go to the store")
    }

    func testMiniMaxParserHandlesCleanJSONDirectly() throws {
        let content = """
        {
          "recommendedCategoryId": "work",
          "confidence": 0.75,
          "title": "Review meeting notes",
          "blocks": [
            { "type": "bullet", "content": "Summarize action items", "checked": false }
          ],
          "needsClarification": false,
          "questionsForUser": []
        }
        """

        let draft = try MiniMaxDraftParser.parse(content, captureItemId: UUID(), generatedByProvider: "minimax")
        XCTAssertEqual(draft.title, "Review meeting notes")
        XCTAssertEqual(draft.confidence, 0.75)
    }
}
