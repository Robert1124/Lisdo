import XCTest
@testable import LisdoCore

final class TaskDraftProviderOutputRetryTests: XCTestCase {
    func testRetriesDraftParsingFailuresBeforeReturningSuccess() async throws {
        let provider = SequencedRetryProvider(results: [
            .failure(DraftParsingError.invalidJSON),
            .failure(DraftParsingError.missingRequiredField("title")),
            .success(makeDraft(title: "Recovered draft"))
        ])

        let draft = try await TaskDraftProviderOutputRetry.generateDraft(
            provider: provider,
            input: makeInput(),
            categories: [],
            options: TaskDraftProviderOptions(model: "test"),
            retryDelayNanoseconds: 0
        )

        XCTAssertEqual(draft.title, "Recovered draft")
        XCTAssertEqual(provider.attemptCount, 3)
    }

    func testStopsAfterMaximumRetryableOutputAttempts() async {
        let provider = SequencedRetryProvider(results: [
            .failure(DraftParsingError.invalidJSON),
            .failure(DraftParsingError.invalidJSON),
            .failure(DraftParsingError.invalidJSON),
            .success(makeDraft(title: "Too late"))
        ])

        do {
            _ = try await TaskDraftProviderOutputRetry.generateDraft(
                provider: provider,
                input: makeInput(),
                categories: [],
                options: TaskDraftProviderOptions(model: "test"),
                maximumAttempts: 3,
                retryDelayNanoseconds: 0
            )
            XCTFail("Expected retry exhaustion to throw.")
        } catch {
            XCTAssertTrue(error is DraftParsingError)
            XCTAssertEqual(provider.attemptCount, 3)
        }
    }

    func testRetriesTransientProviderFailuresBeforeReturningSuccess() async throws {
        let provider = SequencedRetryProvider(results: [
            .failure(ProviderFailure(classification: .retryableTransient)),
            .failure(ProviderFailure(classification: .retryableTransient)),
            .success(makeDraft(title: "Recovered from transient provider failure"))
        ])

        let draft = try await TaskDraftProviderOutputRetry.generateDraft(
            provider: provider,
            input: makeInput(),
            categories: [],
            options: TaskDraftProviderOptions(model: "test"),
            retryDelayNanoseconds: 0
        )

        XCTAssertEqual(draft.title, "Recovered from transient provider failure")
        XCTAssertEqual(provider.attemptCount, 3)
    }

    func testRetriesTransientURLErrorBeforeReturningSuccess() async throws {
        let provider = SequencedRetryProvider(results: [
            .failure(URLError(.timedOut)),
            .success(makeDraft(title: "Recovered from timeout"))
        ])

        let draft = try await TaskDraftProviderOutputRetry.generateDraft(
            provider: provider,
            input: makeInput(),
            categories: [],
            options: TaskDraftProviderOptions(model: "test"),
            retryDelayNanoseconds: 0
        )

        XCTAssertEqual(draft.title, "Recovered from timeout")
        XCTAssertEqual(provider.attemptCount, 2)
    }

    func testDoesNotRetryNonRetryableProviderFailures() async {
        let provider = SequencedRetryProvider(results: [
            .failure(ProviderFailure(classification: .nonRetryable)),
            .success(makeDraft(title: "Should not run"))
        ])

        do {
            _ = try await TaskDraftProviderOutputRetry.generateDraft(
                provider: provider,
                input: makeInput(),
                categories: [],
                options: TaskDraftProviderOptions(model: "test"),
                retryDelayNanoseconds: 0
            )
            XCTFail("Expected non-retryable provider failure to throw immediately.")
        } catch {
            XCTAssertEqual(provider.attemptCount, 1)
        }
    }

    func testHTTPRetryStatusPolicyOnlyIncludesTransientStatuses() {
        for statusCode in [408, 429, 500, 502, 503, 504] {
            XCTAssertTrue(
                TaskDraftProviderOutputRetry.isTransientHTTPStatus(statusCode),
                "Expected \(statusCode) to be retryable."
            )
        }

        for statusCode in [400, 401, 402, 403, 404, 422] {
            XCTAssertFalse(
                TaskDraftProviderOutputRetry.isTransientHTTPStatus(statusCode),
                "Expected \(statusCode) to be non-retryable."
            )
        }
    }

    func testDoesNotRetryNonOutputFailures() async {
        let provider = SequencedRetryProvider(results: [
            .failure(NonOutputProviderFailure()),
            .success(makeDraft(title: "Should not run"))
        ])

        do {
            _ = try await TaskDraftProviderOutputRetry.generateDraft(
                provider: provider,
                input: makeInput(),
                categories: [],
                options: TaskDraftProviderOptions(model: "test"),
                retryDelayNanoseconds: 0
            )
            XCTFail("Expected non-output failure to throw immediately.")
        } catch {
            XCTAssertTrue(error is NonOutputProviderFailure)
            XCTAssertEqual(provider.attemptCount, 1)
        }
    }

    private func makeInput() -> TaskDraftInput {
        TaskDraftInput(captureItemId: UUID(), sourceText: "Review paper")
    }

    private func makeDraft(title: String) -> ProcessingDraft {
        ProcessingDraft(
            captureItemId: UUID(),
            title: title,
            blocks: [
                DraftBlock(type: .checkbox, content: "Review source", order: 0)
            ]
        )
    }
}

private struct NonOutputProviderFailure: Error {}

private struct ProviderFailure: Error, TaskDraftProviderRetryClassifying {
    var classification: TaskDraftProviderRetryClassification

    var taskDraftRetryClassification: TaskDraftProviderRetryClassification {
        classification
    }
}

private final class SequencedRetryProvider: TaskDraftProvider, @unchecked Sendable {
    let id = "sequenced-retry-provider"
    let displayName = "Sequenced Retry Provider"
    let mode = ProviderMode.openAICompatibleBYOK

    private var results: [Result<ProcessingDraft, Error>]
    private(set) var attemptCount = 0

    init(results: [Result<ProcessingDraft, Error>]) {
        self.results = results
    }

    func generateDraft(
        input: TaskDraftInput,
        categories: [LisdoCore.Category],
        options: TaskDraftProviderOptions
    ) async throws -> ProcessingDraft {
        attemptCount += 1
        guard !results.isEmpty else {
            throw DraftParsingError.invalidJSON
        }
        return try results.removeFirst().get()
    }
}
