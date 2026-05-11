import Foundation

public struct TaskDraftInput: Equatable, Sendable {
    public var captureItemId: UUID
    public var sourceText: String
    public var userNote: String?
    public var preferredSchemaPreset: CategorySchemaPreset?
    public var revisionInstructions: String?
    public var captureCreatedAt: Date?
    public var timeZoneIdentifier: String?
    public var imageAttachment: TaskDraftImageAttachment?
    public var audioAttachment: TaskDraftAudioAttachment?
    public var additionalImageAttachments: [TaskDraftImageAttachment]
    public var additionalAudioAttachments: [TaskDraftAudioAttachment]

    public init(
        captureItemId: UUID,
        sourceText: String,
        userNote: String? = nil,
        preferredSchemaPreset: CategorySchemaPreset? = nil,
        revisionInstructions: String? = nil,
        captureCreatedAt: Date? = nil,
        timeZoneIdentifier: String? = nil,
        imageAttachment: TaskDraftImageAttachment? = nil,
        audioAttachment: TaskDraftAudioAttachment? = nil,
        additionalImageAttachments: [TaskDraftImageAttachment] = [],
        additionalAudioAttachments: [TaskDraftAudioAttachment] = []
    ) {
        self.captureItemId = captureItemId
        self.sourceText = sourceText
        self.userNote = userNote
        self.preferredSchemaPreset = preferredSchemaPreset
        self.revisionInstructions = revisionInstructions
        self.captureCreatedAt = captureCreatedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.imageAttachment = imageAttachment
        self.audioAttachment = audioAttachment
        self.additionalImageAttachments = additionalImageAttachments
        self.additionalAudioAttachments = additionalAudioAttachments
    }

    public var allImageAttachments: [TaskDraftImageAttachment] {
        [imageAttachment].compactMap { $0 } + additionalImageAttachments
    }

    public var allAudioAttachments: [TaskDraftAudioAttachment] {
        [audioAttachment].compactMap { $0 } + additionalAudioAttachments
    }
}

public struct TaskDraftImageAttachment: Equatable, Sendable {
    public var data: Data
    public var mimeType: String
    public var filename: String?

    public init(data: Data, mimeType: String, filename: String? = nil) {
        self.data = data
        self.mimeType = mimeType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "image/png"
            : mimeType.trimmingCharacters(in: .whitespacesAndNewlines)
        self.filename = filename?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct TaskDraftAudioAttachment: Equatable, Sendable {
    public var data: Data
    public var format: String
    public var filename: String?

    public init(data: Data, format: String, filename: String? = nil) {
        let trimmedFormat = format.trimmingCharacters(in: .whitespacesAndNewlines)
        self.data = data
        self.format = trimmedFormat.isEmpty ? "m4a" : trimmedFormat
        self.filename = filename?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct TaskDraftProviderOptions: Equatable, Sendable {
    public var model: String
    public var temperature: Double
    public var maximumOutputTokens: Int?

    public init(model: String, temperature: Double = 0.1, maximumOutputTokens: Int? = nil) {
        self.model = model
        self.temperature = temperature
        self.maximumOutputTokens = maximumOutputTokens
    }
}

public protocol TaskDraftProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var mode: ProviderMode { get }

    func generateDraft(
        input: TaskDraftInput,
        categories: [Category],
        options: TaskDraftProviderOptions
    ) async throws -> ProcessingDraft
}

public protocol OpenAICompatibleDraftRequestBuilding: Sendable {
    func makeRequest(
        input: TaskDraftInput,
        categories: [Category],
        options: TaskDraftProviderOptions
    ) -> OpenAICompatibleChatRequest
}

public struct OpenAICompatibleDraftRequestBuilder: OpenAICompatibleDraftRequestBuilding {
    public init() {}

    public func makeRequest(
        input: TaskDraftInput,
        categories: [Category],
        options: TaskDraftProviderOptions
    ) -> OpenAICompatibleChatRequest {
        return OpenAICompatibleChatRequest(
            model: options.model,
            messages: [
                .init(role: .system, content: TaskDraftPromptBuilder.systemPrompt),
                .init(role: .user, content: TaskDraftPromptBuilder.openAICompatibleUserContent(input: input, categories: categories))
            ],
            temperature: options.temperature,
            maxTokens: options.maximumOutputTokens,
            responseFormat: .jsonObject
        )
    }
}

public struct MiniMaxOpenAICompatibleDraftRequestBuilder: OpenAICompatibleDraftRequestBuilding {
    public init() {}

    public func makeRequest(
        input: TaskDraftInput,
        categories: [Category],
        options: TaskDraftProviderOptions
    ) -> OpenAICompatibleChatRequest {
        var request = OpenAICompatibleDraftRequestBuilder().makeRequest(
            input: input,
            categories: categories,
            options: options
        )
        request.reasoningSplit = true
        return request
    }
}

public struct OpenAICompatibleChatRequest: Codable, Equatable, Sendable {
    public var model: String
    public var messages: [OpenAICompatibleMessage]
    public var temperature: Double
    public var maxTokens: Int?
    public var responseFormat: OpenAICompatibleResponseFormat
    public var reasoningSplit: Bool?

    public init(
        model: String,
        messages: [OpenAICompatibleMessage],
        temperature: Double,
        maxTokens: Int?,
        responseFormat: OpenAICompatibleResponseFormat,
        reasoningSplit: Bool? = nil
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.responseFormat = responseFormat
        self.reasoningSplit = reasoningSplit
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
        case reasoningSplit = "reasoning_split"
    }
}

public struct OpenAICompatibleMessage: Codable, Equatable, Sendable {
    public var role: OpenAICompatibleRole
    public var content: OpenAICompatibleMessageContent

    public init(role: OpenAICompatibleRole, content: String) {
        self.role = role
        self.content = .text(content)
    }

    public init(role: OpenAICompatibleRole, content: OpenAICompatibleMessageContent) {
        self.role = role
        self.content = content
    }
}

public enum OpenAICompatibleMessageContent: Codable, Equatable, Sendable {
    case text(String)
    case parts([OpenAICompatibleContentPart])

    public var plainText: String {
        switch self {
        case .text(let value):
            return value
        case .parts(let parts):
            return parts.compactMap(\.textValue).joined(separator: "\n")
        }
    }

    public func contains(_ other: String) -> Bool {
        plainText.contains(other)
    }

    public func localizedCaseInsensitiveContains(_ other: String) -> Bool {
        plainText.localizedCaseInsensitiveContains(other)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }
        self = .parts(try container.decode([OpenAICompatibleContentPart].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .parts(let parts):
            try container.encode(parts)
        }
    }
}

public enum OpenAICompatibleContentPart: Codable, Equatable, Sendable {
    case text(String)
    case imageURL(String)
    case inputAudio(data: String, format: String)

    public var textValue: String? {
        if case .text(let text) = self {
            return text
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
        case inputAudio = "input_audio"
    }

    private enum ImageURLCodingKeys: String, CodingKey {
        case url
    }

    private enum InputAudioCodingKeys: String, CodingKey {
        case data
        case format
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "image_url":
            let imageContainer = try container.nestedContainer(keyedBy: ImageURLCodingKeys.self, forKey: .imageURL)
            self = .imageURL(try imageContainer.decode(String.self, forKey: .url))
        case "input_audio":
            let audioContainer = try container.nestedContainer(keyedBy: InputAudioCodingKeys.self, forKey: .inputAudio)
            self = .inputAudio(
                data: try audioContainer.decode(String.self, forKey: .data),
                format: try audioContainer.decode(String.self, forKey: .format)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unsupported content part type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageURL(let url):
            try container.encode("image_url", forKey: .type)
            var imageContainer = container.nestedContainer(keyedBy: ImageURLCodingKeys.self, forKey: .imageURL)
            try imageContainer.encode(url, forKey: .url)
        case .inputAudio(let data, let format):
            try container.encode("input_audio", forKey: .type)
            var audioContainer = container.nestedContainer(keyedBy: InputAudioCodingKeys.self, forKey: .inputAudio)
            try audioContainer.encode(data, forKey: .data)
            try audioContainer.encode(format, forKey: .format)
        }
    }
}

public enum OpenAICompatibleRole: String, Codable, Equatable, Sendable {
    case system
    case user
    case assistant
}

public struct OpenAICompatibleResponseFormat: Codable, Equatable, Sendable {
    public var type: String

    public var requiresJSONObject: Bool {
        type == "json_object"
    }

    public static let jsonObject = OpenAICompatibleResponseFormat(type: "json_object")

    public init(type: String) {
        self.type = type
    }
}

public protocol AnthropicDraftRequestBuilding: Sendable {
    func makeRequest(
        input: TaskDraftInput,
        categories: [Category],
        options: TaskDraftProviderOptions
    ) -> AnthropicMessagesRequest
}

public struct AnthropicDraftRequestBuilder: AnthropicDraftRequestBuilding {
    public init() {}

    public func makeRequest(
        input: TaskDraftInput,
        categories: [Category],
        options: TaskDraftProviderOptions
    ) -> AnthropicMessagesRequest {
        AnthropicMessagesRequest(
            model: options.model,
            maxTokens: options.maximumOutputTokens ?? 1200,
            temperature: options.temperature,
            system: TaskDraftPromptBuilder.systemPrompt,
            messages: [
                AnthropicMessage(role: .user, content: TaskDraftPromptBuilder.userPrompt(input: input, categories: categories))
            ]
        )
    }
}

public struct AnthropicMessagesRequest: Codable, Equatable, Sendable {
    public var model: String
    public var maxTokens: Int
    public var temperature: Double
    public var system: String
    public var messages: [AnthropicMessage]

    public init(
        model: String,
        maxTokens: Int,
        temperature: Double,
        system: String,
        messages: [AnthropicMessage]
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.system = system
        self.messages = messages
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case temperature
        case system
        case messages
    }
}

public struct AnthropicMessage: Codable, Equatable, Sendable {
    public var role: AnthropicRole
    public var content: String

    public init(role: AnthropicRole, content: String) {
        self.role = role
        self.content = content
    }
}

public enum AnthropicRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
}

public protocol GeminiDraftRequestBuilding: Sendable {
    func makeRequest(
        input: TaskDraftInput,
        categories: [Category],
        options: TaskDraftProviderOptions
    ) -> GeminiGenerateContentRequest
}

public struct GeminiDraftRequestBuilder: GeminiDraftRequestBuilding {
    public init() {}

    public func makeRequest(
        input: TaskDraftInput,
        categories: [Category],
        options: TaskDraftProviderOptions
    ) -> GeminiGenerateContentRequest {
        GeminiGenerateContentRequest(
            contents: [
                GeminiContent(
                    role: "user",
                    parts: [
                        GeminiPart(text: """
                        \(TaskDraftPromptBuilder.systemPrompt)

                        \(TaskDraftPromptBuilder.userPrompt(input: input, categories: categories))
                        """)
                    ]
                )
            ],
            generationConfig: GeminiGenerationConfig(
                temperature: options.temperature,
                maxOutputTokens: options.maximumOutputTokens,
                responseMimeType: "application/json"
            )
        )
    }
}

public struct GeminiGenerateContentRequest: Codable, Equatable, Sendable {
    public var contents: [GeminiContent]
    public var generationConfig: GeminiGenerationConfig?

    public init(contents: [GeminiContent], generationConfig: GeminiGenerationConfig? = nil) {
        self.contents = contents
        self.generationConfig = generationConfig
    }
}

public struct GeminiContent: Codable, Equatable, Sendable {
    public var role: String?
    public var parts: [GeminiPart]

    public init(role: String? = nil, parts: [GeminiPart]) {
        self.role = role
        self.parts = parts
    }
}

public struct GeminiPart: Codable, Equatable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

public struct GeminiGenerationConfig: Codable, Equatable, Sendable {
    public var temperature: Double
    public var maxOutputTokens: Int?
    public var responseMimeType: String?

    public init(temperature: Double, maxOutputTokens: Int? = nil, responseMimeType: String? = nil) {
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
        self.responseMimeType = responseMimeType
    }
}

private enum TaskDraftPromptBuilder {
    private static let isoFormatter = ISO8601DateFormatter()

    static let systemPrompt = """
    You generate draft tasks for Lisdo. Return only strict JSON matching this shape:
    {"recommendedCategoryId":"category-id-or-null","confidence":0.0,"title":"short title","summary":"optional summary","blocks":[{"type":"checkbox|bullet|note","content":"text","checked":false}],"suggestedReminders":[{"title":"advance reminder title","reminderDateText":"natural language reminder date","reminderDateISO":"ISO-8601 notification time or null","reason":"why this reminder helps","defaultSelected":true,"order":0}],"dueDateText":"optional natural language due date","dueDateISO":"ISO-8601 deadline or null","scheduledDateISO":"ISO-8601 event/start time or null","dateResolutionReferenceISO":"ISO-8601 timestamp used to resolve relative dates or null","priority":"low|medium|high|null","needsClarification":false,"questionsForUser":[]}
    Resolve relative dates like today, tomorrow, tonight, this Friday, and the day before into ISO-8601 timestamps with timezone offsets when enough context exists.
    Use dueDateISO for deadlines and due-by times. Use scheduledDateISO for events, appointments, classes, meetings, or concrete start times.
    Use the source timestamp first when the source includes one; otherwise use the capture context supplied below. Preserve the original natural phrase in dueDateText. If the date is ambiguous, leave ISO fields null and ask a clarification question.
    Use suggestedReminders for preparatory or advance reminders under the main todo; do not put those as normal checklist blocks when they are separate reminders. Add reminderDateISO when the reminder time can be resolved to a concrete notification time. Examples: run a tech check the day before, update the computer the day before.
    Never return Markdown. AI output is a draft for user review, not a final todo.
    """

    static func userPrompt(input: TaskDraftInput, categories: [Category]) -> String {
        let categoryLines = categories.map { category in
            "- id: \(category.id), name: \(category.name), preset: \(category.schemaPreset.rawValue), description: \(category.descriptionText), format: \(category.formattingInstruction)"
        }
        .joined(separator: "\n")

        let userNoteLine = input.userNote.map { "\nUser note: \($0)" } ?? ""
        let preferredPresetLine = input.preferredSchemaPreset.map { "\nPreferred schema preset: \($0.rawValue)" } ?? ""
        let revisionInstructionLine = input.revisionInstructions.map {
            "\nRevision instructions: \($0)\nApply these instructions while keeping the result a draft for user review."
        } ?? ""
        let captureContext = captureContextLines(input: input)

        return """
        Source text:
        \(input.sourceText)
        \(userNoteLine)\(preferredPresetLine)\(revisionInstructionLine)\(captureContext)

        Available categories:
        \(categoryLines)
        """
    }

    static func openAICompatibleUserContent(input: TaskDraftInput, categories: [Category]) -> OpenAICompatibleMessageContent {
        let prompt = userPrompt(input: input, categories: categories)
        var parts: [OpenAICompatibleContentPart] = [.text(prompt)]

        for imageAttachment in input.allImageAttachments {
            let dataURL = "data:\(imageAttachment.mimeType);base64,\(imageAttachment.data.base64EncodedString())"
            parts.append(.imageURL(dataURL))
        }

        for audioAttachment in input.allAudioAttachments {
            parts.append(.inputAudio(data: audioAttachment.data.base64EncodedString(), format: audioAttachment.format))
        }

        guard parts.count > 1 else {
            return .text(prompt)
        }
        return .parts(parts)
    }

    private static func captureContextLines(input: TaskDraftInput) -> String {
        var lines: [String] = []
        if let captureCreatedAt = input.captureCreatedAt {
            lines.append("captureCreatedAt: \(isoFormatter.string(from: captureCreatedAt))")
        }
        if let timeZoneIdentifier = input.timeZoneIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !timeZoneIdentifier.isEmpty {
            lines.append("userTimeZone: \(timeZoneIdentifier)")
        }
        for (index, imageAttachment) in input.allImageAttachments.enumerated() {
            let filename = imageAttachment.filename?.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = input.allImageAttachments.count > 1 ? "directImageAttachment\(index + 1)" : "directImageAttachment"
            lines.append("\(label): \(filename?.isEmpty == false ? filename! : imageAttachment.mimeType)")
            lines.append("imageInstruction: Read visible text, layout, tables, and formatting directly from the image attachment. Do not require OCR text if the image is attached.")
        }
        for (index, audioAttachment) in input.allAudioAttachments.enumerated() {
            let filename = audioAttachment.filename?.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = input.allAudioAttachments.count > 1 ? "directAudioAttachment\(index + 1)" : "directAudioAttachment"
            lines.append("\(label): \(filename?.isEmpty == false ? filename! : audioAttachment.format)")
            lines.append("audioInstruction: Transcribe and extract tasks directly from the audio attachment. The result must still be draft-first JSON.")
        }
        guard !lines.isEmpty else { return "" }
        return "\n\nCapture context:\n" + lines.map { "- \($0)" }.joined(separator: "\n")
    }
}
