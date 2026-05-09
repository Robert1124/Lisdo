import Foundation
import LisdoCore

public enum OpenAICompatibleDraftProviderError: Error, Equatable, Sendable {
    case invalidHTTPResponse
    case httpStatus(Int)
    case missingAssistantContent
}

public enum OpenAICompatibleDraftContentParsingMode: Sendable {
    case strict
    case miniMax
}

public final class OpenAICompatibleDraftProvider: TaskDraftProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String
    public let mode: ProviderMode
    public let endpointURL: URL
    public let model: String

    private let apiKey: String?
    private let urlSession: URLSession
    private let requestBuilder: any OpenAICompatibleDraftRequestBuilding
    private let contentParsingMode: OpenAICompatibleDraftContentParsingMode
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        endpointURL: URL,
        apiKey: String?,
        model: String,
        id: String = "openai-compatible-byok",
        displayName: String = "OpenAI-compatible BYOK",
        mode: ProviderMode = .openAICompatibleBYOK,
        urlSession: URLSession = .shared,
        requestBuilder: any OpenAICompatibleDraftRequestBuilding = OpenAICompatibleDraftRequestBuilder(),
        contentParsingMode: OpenAICompatibleDraftContentParsingMode = .strict
    ) {
        self.endpointURL = endpointURL
        self.apiKey = apiKey
        self.model = model
        self.id = id
        self.displayName = displayName
        self.mode = mode
        self.urlSession = urlSession
        self.requestBuilder = requestBuilder
        self.contentParsingMode = contentParsingMode
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public convenience init(
        baseURL: URL,
        apiKey: String?,
        model: String,
        id: String = "openai-compatible-byok",
        displayName: String = "OpenAI-compatible BYOK",
        mode: ProviderMode = .openAICompatibleBYOK,
        urlSession: URLSession = .shared,
        requestBuilder: any OpenAICompatibleDraftRequestBuilding = OpenAICompatibleDraftRequestBuilder(),
        contentParsingMode: OpenAICompatibleDraftContentParsingMode = .strict
    ) {
        self.init(
            endpointURL: OpenAICompatibleDraftProvider.chatCompletionsEndpoint(from: baseURL),
            apiKey: apiKey,
            model: model,
            id: id,
            displayName: displayName,
            mode: mode,
            urlSession: urlSession,
            requestBuilder: requestBuilder,
            contentParsingMode: contentParsingMode
        )
    }

    public func generateDraft(
        input: TaskDraftInput,
        categories: [LisdoCore.Category],
        options: TaskDraftProviderOptions
    ) async throws -> ProcessingDraft {
        let effectiveOptions = TaskDraftProviderOptions(
            model: model,
            temperature: options.temperature,
            maximumOutputTokens: options.maximumOutputTokens
        )
        let chatRequest = requestBuilder.makeRequest(
            input: input,
            categories: categories,
            options: effectiveOptions
        )

        var urlRequest = URLRequest(url: endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try encoder.encode(chatRequest)

        let (data, response) = try await urlSession.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAICompatibleDraftProviderError.invalidHTTPResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenAICompatibleDraftProviderError.httpStatus(httpResponse.statusCode)
        }

        let chatResponse = try decoder.decode(OpenAICompatibleChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty
        else {
            throw OpenAICompatibleDraftProviderError.missingAssistantContent
        }

        return try parseDraftContent(content, input: input)
    }

    private func parseDraftContent(_ content: String, input: TaskDraftInput) throws -> ProcessingDraft {
        switch contentParsingMode {
        case .strict:
            return try TaskDraftParser.parse(
                content,
                captureItemId: input.captureItemId,
                generatedByProvider: "\(id):\(model)"
            )
        case .miniMax:
            return try MiniMaxDraftParser.parse(
                content,
                captureItemId: input.captureItemId,
                generatedByProvider: "\(id):\(model)"
            )
        }
    }

    private static func chatCompletionsEndpoint(from baseURL: URL) -> URL {
        if baseURL.path.hasSuffix("/chat/completions") {
            return baseURL
        }

        return baseURL
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
    }
}

private struct OpenAICompatibleChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }
}
