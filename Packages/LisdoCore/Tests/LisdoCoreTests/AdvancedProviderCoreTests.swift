import XCTest
@testable import LisdoCore

final class AdvancedProviderCoreTests: XCTestCase {
    func testFallbackProviderReturnsFirstSuccessfulDraftAndRecordsAttempts() async throws {
        let input = TaskDraftInput(captureItemId: UUID(), sourceText: "Send Yan the revised questionnaire.")
        let categories = [Category(id: "work", name: "Work")]
        let options = TaskDraftProviderOptions(model: "fallback")
        let expectedDraft = ProcessingDraft(
            captureItemId: input.captureItemId,
            recommendedCategoryId: "work",
            title: "Send questionnaire",
            generatedByProvider: "second-provider"
        )
        let first = StubTaskDraftProvider(
            id: "first-provider",
            displayName: "First Provider",
            mode: .anthropic,
            result: .failure(StubProviderError.failed)
        )
        let second = StubTaskDraftProvider(
            id: "second-provider",
            displayName: "Second Provider",
            mode: .gemini,
            result: .success(expectedDraft)
        )
        let fallback = TaskDraftFallbackProvider(id: "fallback", displayName: "Fallback", providers: [first, second])

        let draft = try await fallback.generateDraft(input: input, categories: categories, options: options)

        XCTAssertTrue(draft === expectedDraft)
        XCTAssertEqual(fallback.lastAttempts.map(\.providerId), ["first-provider", "second-provider"])
        XCTAssertEqual(fallback.lastAttempts.map(\.outcome), [.failure, .success])
        XCTAssertTrue(fallback.lastAttempts[0].errorDescription?.contains("failed") == true)
    }

    func testFallbackProviderThrowsAttemptedProviderIdsWhenAllFail() async {
        let input = TaskDraftInput(captureItemId: UUID(), sourceText: "Call Yan.")
        let providers = [
            StubTaskDraftProvider(id: "anthropic", displayName: "Anthropic", mode: .anthropic, result: .failure(StubProviderError.failed)),
            StubTaskDraftProvider(id: "gemini", displayName: "Gemini", mode: .gemini, result: .failure(StubProviderError.failed))
        ]
        let fallback = TaskDraftFallbackProvider(id: "fallback", displayName: "Fallback", providers: providers)

        do {
            _ = try await fallback.generateDraft(input: input, categories: [], options: TaskDraftProviderOptions(model: "fallback"))
            XCTFail("Expected fallback failure")
        } catch let error as TaskDraftFallbackError {
            XCTAssertEqual(error.attemptedProviderIds, ["anthropic", "gemini"])
            XCTAssertEqual(fallback.lastAttempts.map(\.outcome), [.failure, .failure])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProviderRequestBuildersIncludeRevisionInstructionsAndCategorySchemaRules() {
        let input = TaskDraftInput(
            captureItemId: UUID(),
            sourceText: "Revise the questionnaire and confirm Zoom recording.",
            userNote: "This is for class operations.",
            preferredSchemaPreset: .checklist,
            revisionInstructions: "Make the checklist more explicit and keep the result concise."
        )
        let categories = [
            Category(
                id: "work",
                name: "Work",
                descriptionText: "Work and study operations",
                formattingInstruction: "Use imperative checklist items with owners when possible.",
                schemaPreset: .meeting
            )
        ]
        let options = TaskDraftProviderOptions(model: "test-model", temperature: 0.2, maximumOutputTokens: 900)

        let openAI = OpenAICompatibleDraftRequestBuilder().makeRequest(input: input, categories: categories, options: options)
        let anthropic = AnthropicDraftRequestBuilder().makeRequest(input: input, categories: categories, options: options)
        let gemini = GeminiDraftRequestBuilder().makeRequest(input: input, categories: categories, options: options)

        for content in [
            openAI.messages.map(\.content.plainText).joined(separator: "\n"),
            anthropic.system + "\n" + anthropic.messages.map(\.content).joined(separator: "\n"),
            gemini.contents.flatMap(\.parts).map(\.text).joined(separator: "\n")
        ] {
            XCTAssertTrue(content.contains("Make the checklist more explicit"))
            XCTAssertTrue(content.contains("draft for user review"))
            XCTAssertTrue(content.contains("format: Use imperative checklist items"))
            XCTAssertTrue(content.contains("preset: meeting"))
            XCTAssertTrue(content.contains("Preferred schema preset: checklist"))
        }

        XCTAssertEqual(anthropic.model, "test-model")
        XCTAssertEqual(anthropic.maxTokens, 900)
        XCTAssertEqual(gemini.generationConfig?.temperature, 0.2)
        XCTAssertEqual(gemini.generationConfig?.maxOutputTokens, 900)
    }
}

private enum StubProviderError: Error {
    case failed
}

private final class StubTaskDraftProvider: TaskDraftProvider, @unchecked Sendable {
    let id: String
    let displayName: String
    let mode: ProviderMode
    let result: Result<ProcessingDraft, Error>

    init(id: String, displayName: String, mode: ProviderMode, result: Result<ProcessingDraft, Error>) {
        self.id = id
        self.displayName = displayName
        self.mode = mode
        self.result = result
    }

    func generateDraft(
        input: TaskDraftInput,
        categories: [LisdoCore.Category],
        options: TaskDraftProviderOptions
    ) async throws -> ProcessingDraft {
        try result.get()
    }
}
