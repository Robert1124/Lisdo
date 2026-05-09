import XCTest
@testable import LisdoCore

final class CLIProviderContractTests: XCTestCase {
    func testValidStrictCLIJSONOutputParsesToProcessingDraftOnly() throws {
        let captureId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let stdout = """
        {
          "recommendedCategoryId": "work",
          "confidence": 0.91,
          "title": "Send questionnaire to Yan",
          "summary": "Revise the questionnaire and send it for review.",
          "blocks": [
            { "type": "checkbox", "content": "Revise the questionnaire", "checked": false },
            { "type": "checkbox", "content": "Send it to Yan", "checked": false }
          ],
          "dueDateText": "tomorrow before 3 PM",
          "priority": "high",
          "needsClarification": false,
          "questionsForUser": []
        }
        """
        let provider = CLIDraftProviderDescriptor.codex()

        let draft = try CLIStrictDraftParser.parseStdout(
            stdout,
            captureItemId: captureId,
            provider: provider,
            generatedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(draft.captureItemId, captureId)
        XCTAssertEqual(draft.generatedByProvider, provider.id)
        XCTAssertEqual(draft.title, "Send questionnaire to Yan")
        XCTAssertEqual(draft.blocks.count, 2)
        XCTAssertThrowsError(try DraftApprovalConverter.convert(draft, categoryId: "work", approval: nil)) { error in
            XCTAssertEqual(error as? DraftApprovalError, .approvalRequired)
        }
    }

    func testInvalidOrFreeFormCLIOutputThrowsInvalidJSONAndCreatesNoTodo() {
        XCTAssertThrowsError(
            try CLIStrictDraftParser.parseStdout(
                "Sure, here is a task:\n- [ ] Send it to Yan",
                captureItemId: UUID(),
                provider: .claudeCode()
            )
        ) { error in
            XCTAssertEqual(
                error as? CLIProviderError,
                .invalidJSON(providerId: "claude-code", providerName: "Claude Code CLI")
            )
        }
    }

    func testTimeoutAndNonZeroExitResultsMapToFailedCaptureState() throws {
        let timeoutCapture = CaptureItem(
            sourceType: .shareExtension,
            sourceText: "Please handle this",
            createdDevice: .iPhone,
            status: .processing,
            preferredProviderMode: .macOnlyCLI,
            processingLockDeviceId: "mac-a",
            processingLockCreatedAt: Date(timeIntervalSince1970: 10)
        )

        let timeoutError = CLIProviderError.timedOut(providerId: "codex-cli", providerName: "Codex CLI", timeoutSeconds: 60)
        try timeoutCapture.markCLIProcessingFailed(timeoutError)

        XCTAssertEqual(timeoutCapture.status, .failed)
        XCTAssertEqual(timeoutCapture.processingError, "Codex CLI timed out after 60 seconds.")
        XCTAssertNil(timeoutCapture.processingLockDeviceId)
        XCTAssertNil(timeoutCapture.processingLockCreatedAt)

        let nonZeroCapture = CaptureItem(
            sourceType: .textPaste,
            sourceText: "Please handle this too",
            createdDevice: .mac,
            status: .processing,
            preferredProviderMode: .macOnlyCLI
        )

        let exitError = CLIProviderError.nonZeroExit(providerId: "gemini-cli", providerName: "Gemini CLI", exitCode: 2, stderr: "auth missing")
        try nonZeroCapture.markCLIProcessingFailed(exitError)

        XCTAssertEqual(nonZeroCapture.status, .failed)
        XCTAssertEqual(nonZeroCapture.processingError, "Gemini CLI exited with code 2: auth missing")
    }

    func testPendingRetryAndStaleLeaseTransitionsForMacProcessing() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let capture = CaptureItem(
            sourceType: .voiceNote,
            sourceText: "old raw text",
            transcriptText: "  Call Yan about the questionnaire  ",
            createdDevice: .iPhone,
            status: .pendingProcessing,
            preferredProviderMode: .macOnlyCLI
        )

        XCTAssertTrue(capture.isMacProcessablePending(now: now))
        try capture.leaseForMacProcessing(processorDeviceId: "mac-a", now: now)

        XCTAssertEqual(capture.status, .processing)
        XCTAssertEqual(capture.assignedProcessorDeviceId, "mac-a")
        XCTAssertEqual(capture.processingLockDeviceId, "mac-a")
        XCTAssertEqual(capture.processingLockCreatedAt, now)
        XCTAssertNil(capture.processingError)

        let staleNow = now.addingTimeInterval(901)
        XCTAssertTrue(capture.isMacProcessablePending(now: staleNow, staleLockInterval: 900))
        try capture.leaseForMacProcessing(processorDeviceId: "mac-b", now: staleNow, staleLockInterval: 900)

        XCTAssertEqual(capture.status, .processing)
        XCTAssertEqual(capture.assignedProcessorDeviceId, "mac-b")
        XCTAssertEqual(capture.processingLockDeviceId, "mac-b")
        XCTAssertEqual(capture.processingLockCreatedAt, staleNow)

        try capture.markCLIProcessingFailed(.nonZeroExit(providerId: "codex-cli", providerName: "Codex CLI", exitCode: 1, stderr: "bad json"))
        try capture.queueForRetry()
        XCTAssertEqual(capture.status, .retryPending)

        try capture.leaseForMacProcessing(processorDeviceId: "mac-a", now: staleNow.addingTimeInterval(1))
        XCTAssertEqual(capture.status, .processing)
    }

    func testSuccessfulCLIProcessingMarksProcessedDraftWithoutCreatingTodo() throws {
        let capture = CaptureItem(
            sourceType: .textPaste,
            sourceText: "Send the questionnaire to Yan.",
            createdDevice: .mac,
            status: .pendingProcessing,
            preferredProviderMode: .macOnlyCLI
        )
        try capture.leaseForMacProcessing(processorDeviceId: "mac-a", now: Date(timeIntervalSince1970: 50))

        let draft = ProcessingDraft(
            captureItemId: capture.id,
            recommendedCategoryId: "work",
            title: "Send questionnaire",
            blocks: [
                DraftBlock(type: .checkbox, content: "Send questionnaire to Yan", order: 0)
            ],
            generatedByProvider: "codex-cli"
        )

        let returnedDraft = try capture.markCLIProcessingSucceeded(with: draft)

        XCTAssertTrue(returnedDraft === draft)
        XCTAssertEqual(capture.status, .processedDraft)
        XCTAssertNil(capture.processingLockDeviceId)
        XCTAssertNil(capture.processingLockCreatedAt)
        XCTAssertThrowsError(try DraftApprovalConverter.convert(returnedDraft, categoryId: "work", approval: nil)) { error in
            XCTAssertEqual(error as? DraftApprovalError, .approvalRequired)
        }
    }

    func testTranscriptNormalizationPrefersTranscriptAndRejectsEmptyContent() throws {
        let voiceCapture = CaptureItem(
            sourceType: .voiceNote,
            sourceText: "stale pre-transcript text",
            transcriptText: "  remind me to update the questionnaire  ",
            createdDevice: .iPhone,
            preferredProviderMode: .macOnlyCLI
        )

        XCTAssertEqual(try voiceCapture.normalizedProcessableText(), "remind me to update the questionnaire")

        let textCapture = CaptureItem(
            sourceType: .textPaste,
            sourceText: "  pasted task  ",
            transcriptText: "   ",
            createdDevice: .mac,
            preferredProviderMode: .openAICompatibleBYOK
        )

        XCTAssertEqual(try textCapture.normalizedProcessableText(), "pasted task")

        let emptyCapture = CaptureItem(
            sourceType: .shareExtension,
            sourceText: "  \n\t  ",
            createdDevice: .iPhone,
            preferredProviderMode: .macOnlyCLI
        )

        XCTAssertThrowsError(try emptyCapture.normalizedProcessableText()) { error in
            XCTAssertEqual(error as? CaptureContentNormalizationError, .emptyContent)
        }
    }

    func testCLIProviderStrategiesBuildCommandDTOsWithoutSyncedSecretsOrPaths() throws {
        let input = TaskDraftInput(
            captureItemId: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            sourceText: "Send the questionnaire to Yan.",
            userNote: "Use concise checklist"
        )
        let categories = [
            Category(id: "work", name: "Work", descriptionText: "Work tasks", formattingInstruction: "Checklist", schemaPreset: .checklist)
        ]
        let options = TaskDraftProviderOptions(model: "default", maximumOutputTokens: 800)
        let strategy = CLIDraftCommandStrategy(provider: .gemini())

        let command = strategy.makeCommand(input: input, categories: categories, options: options)

        XCTAssertEqual(command.executableName, "gemini")
        XCTAssertTrue(command.arguments.contains("--prompt"))
        XCTAssertTrue(command.prompt.contains("Return only strict JSON"))
        XCTAssertTrue(command.prompt.contains("Send the questionnaire to Yan."))
        XCTAssertTrue(command.prompt.contains("id: work"))
        XCTAssertNil(command.executablePath)
        XCTAssertTrue(command.environment.isEmpty)
    }
}
