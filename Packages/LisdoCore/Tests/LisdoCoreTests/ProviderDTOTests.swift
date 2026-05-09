import XCTest
@testable import LisdoCore

final class ProviderDTOTests: XCTestCase {
    func testProviderModeCodableIncludesMiniMaxRawValue() throws {
        XCTAssertEqual(ProviderMode.minimax.rawValue, "minimax")

        let encoded = try JSONEncoder().encode(ProviderMode.minimax)
        let decoded = try JSONDecoder().decode(ProviderMode.self, from: encoded)

        XCTAssertEqual(decoded, .minimax)
        XCTAssertTrue(ProviderMode.allCases.contains(.minimax))
    }

    func testOpenAICompatibleRequestBuilderCreatesStrictJSONRequestWithoutSecrets() throws {
        let input = TaskDraftInput(
            captureItemId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            sourceText: "Revise the questionnaire and send it to Yan.",
            userNote: "Work category preferred"
        )
        let categories = [
            Category(id: "work", name: "Work", descriptionText: "Work tasks", formattingInstruction: "Use checklist", schemaPreset: .checklist)
        ]
        let options = TaskDraftProviderOptions(model: "gpt-4.1-mini", temperature: 0.1)

        let request = OpenAICompatibleDraftRequestBuilder().makeRequest(input: input, categories: categories, options: options)

        XCTAssertEqual(request.model, "gpt-4.1-mini")
        XCTAssertEqual(request.temperature, 0.1)
        XCTAssertTrue(request.responseFormat.requiresJSONObject)
        XCTAssertEqual(request.messages.first?.role, .system)
        XCTAssertEqual(request.messages.last?.role, .user)
        XCTAssertTrue(request.messages.last?.content.contains("Revise the questionnaire") == true)
        XCTAssertFalse(request.messages.contains { $0.content.localizedCaseInsensitiveContains("api key") })
    }

    func testMiniMaxRequestBuilderAddsReasoningSplitRequestFieldWithoutSecrets() throws {
        let input = TaskDraftInput(
            captureItemId: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            sourceText: "Confirm Zoom recording settings.",
            userNote: "Work category preferred"
        )
        let categories = [
            Category(id: "work", name: "Work", descriptionText: "Work tasks", formattingInstruction: "Use checklist", schemaPreset: .checklist)
        ]
        let options = TaskDraftProviderOptions(model: "MiniMax-M2.7", temperature: 0.1, maximumOutputTokens: 1200)

        let request = MiniMaxOpenAICompatibleDraftRequestBuilder().makeRequest(input: input, categories: categories, options: options)
        let encoded = try JSONEncoder().encode(request)
        let jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(request.model, "MiniMax-M2.7")
        XCTAssertEqual(request.reasoningSplit, true)
        XCTAssertEqual(jsonObject["reasoning_split"] as? Bool, true)
        XCTAssertFalse(jsonObject.keys.contains("extra_body"))
        XCTAssertFalse(jsonObject.keys.contains("api_key"))
        XCTAssertFalse(jsonObject.keys.contains("authorization"))
    }

    func testProviderPromptIncludesCanonicalDateSchemaAndCaptureTimeContext() throws {
        let input = TaskDraftInput(
            captureItemId: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            sourceText: "Email sent May 4, 2026 at 3:30 PM. Tacos & Tequila event is tomorrow at 4:00 PM.",
            userNote: "Use email timestamp for relative dates.",
            captureCreatedAt: ISO8601DateFormatter().date(from: "2026-05-04T15:30:00-04:00"),
            timeZoneIdentifier: "America/New_York"
        )
        let request = OpenAICompatibleDraftRequestBuilder().makeRequest(
            input: input,
            categories: [Category(id: "inbox", name: "Inbox")],
            options: TaskDraftProviderOptions(model: "test")
        )

        let prompt = request.messages.map { $0.content.plainText }.joined(separator: "\n")

        XCTAssertTrue(prompt.contains("dueDateISO"))
        XCTAssertTrue(prompt.contains("scheduledDateISO"))
        XCTAssertTrue(prompt.contains("dateResolutionReferenceISO"))
        XCTAssertTrue(prompt.contains("reminderDateISO"))
        XCTAssertTrue(prompt.contains("Use the source timestamp first"))
        XCTAssertTrue(prompt.contains("captureCreatedAt: 2026-05-04T19:30:00Z"))
        XCTAssertTrue(prompt.contains("userTimeZone: America/New_York"))
        XCTAssertTrue(prompt.contains("Preserve the original natural phrase in dueDateText"))
    }

    func testOpenAICompatibleRequestBuilderEncodesDirectImageAttachmentAsContentPart() throws {
        let input = TaskDraftInput(
            captureItemId: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            sourceText: "Image attachment included for direct provider analysis.",
            imageAttachment: TaskDraftImageAttachment(
                data: Data([0x01, 0x02, 0x03]),
                mimeType: "image/png",
                filename: "capture.png"
            )
        )

        let request = OpenAICompatibleDraftRequestBuilder().makeRequest(
            input: input,
            categories: [Category(id: "inbox", name: "Inbox")],
            options: TaskDraftProviderOptions(model: "vision-model")
        )
        let encoded = try JSONEncoder().encode(request)
        let jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let messages = try XCTUnwrap(jsonObject["messages"] as? [[String: Any]])
        let userMessage = try XCTUnwrap(messages.last)
        let content = try XCTUnwrap(userMessage["content"] as? [[String: Any]])

        XCTAssertTrue(content.contains { ($0["type"] as? String) == "text" })
        let imagePart = try XCTUnwrap(content.first { ($0["type"] as? String) == "image_url" })
        let imageURL = try XCTUnwrap(imagePart["image_url"] as? [String: Any])
        XCTAssertEqual(imageURL["url"] as? String, "data:image/png;base64,AQID")
    }

    func testOpenAICompatibleRequestBuilderEncodesDirectAudioAttachmentAsContentPart() throws {
        let input = TaskDraftInput(
            captureItemId: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            sourceText: "Audio attachment included for direct provider analysis.",
            audioAttachment: TaskDraftAudioAttachment(
                data: Data([0x04, 0x05, 0x06]),
                format: "m4a",
                filename: "voice.m4a"
            )
        )

        let request = OpenAICompatibleDraftRequestBuilder().makeRequest(
            input: input,
            categories: [Category(id: "inbox", name: "Inbox")],
            options: TaskDraftProviderOptions(model: "audio-model")
        )
        let encoded = try JSONEncoder().encode(request)
        let jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let messages = try XCTUnwrap(jsonObject["messages"] as? [[String: Any]])
        let userMessage = try XCTUnwrap(messages.last)
        let content = try XCTUnwrap(userMessage["content"] as? [[String: Any]])

        XCTAssertTrue(content.contains { ($0["type"] as? String) == "text" })
        let audioPart = try XCTUnwrap(content.first { ($0["type"] as? String) == "input_audio" })
        let inputAudio = try XCTUnwrap(audioPart["input_audio"] as? [String: Any])
        XCTAssertEqual(inputAudio["data"] as? String, "BAUG")
        XCTAssertEqual(inputAudio["format"] as? String, "m4a")
    }
}
