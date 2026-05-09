import Foundation
import LisdoCore

public enum HostedDraftProviderError: Error, Equatable, Sendable {
    case invalidHTTPResponse
    case httpStatus(Int)
    case missingAssistantContent
}

public final class AnthropicDraftProvider: TaskDraftProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String
    public let mode: ProviderMode = .anthropic
    public let endpointURL: URL
    public let model: String

    private let apiKey: String
    private let urlSession: URLSession
    private let requestBuilder: any AnthropicDraftRequestBuilding
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        endpointURL: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        apiKey: String,
        model: String,
        id: String = "anthropic",
        displayName: String = "Anthropic",
        urlSession: URLSession = .shared,
        requestBuilder: any AnthropicDraftRequestBuilding = AnthropicDraftRequestBuilder()
    ) {
        self.endpointURL = endpointURL
        self.apiKey = apiKey
        self.model = model
        self.id = id
        self.displayName = displayName
        self.urlSession = urlSession
        self.requestBuilder = requestBuilder
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
        let request = requestBuilder.makeRequest(input: input, categories: categories, options: effectiveOptions)

        var urlRequest = URLRequest(url: endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await urlSession.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HostedDraftProviderError.invalidHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HostedDraftProviderError.httpStatus(httpResponse.statusCode)
        }

        let decoded = try decoder.decode(AnthropicMessagesResponse.self, from: data)
        let content = decoded.content
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw HostedDraftProviderError.missingAssistantContent
        }

        return try TaskDraftParser.parse(
            content,
            captureItemId: input.captureItemId,
            generatedByProvider: "\(id):\(model)"
        )
    }
}

public final class GeminiAPIDraftProvider: TaskDraftProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String
    public let mode: ProviderMode = .gemini
    public let endpointURL: URL
    public let model: String

    private let apiKey: String
    private let urlSession: URLSession
    private let requestBuilder: any GeminiDraftRequestBuilding
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
        apiKey: String,
        model: String,
        id: String = "gemini-api",
        displayName: String = "Gemini API",
        urlSession: URLSession = .shared,
        requestBuilder: any GeminiDraftRequestBuilding = GeminiDraftRequestBuilder()
    ) {
        self.endpointURL = baseURL
            .appendingPathComponent("models")
            .appendingPathComponent("\(model):generateContent")
        self.apiKey = apiKey
        self.model = model
        self.id = id
        self.displayName = displayName
        self.urlSession = urlSession
        self.requestBuilder = requestBuilder
    }

    public init(
        endpointURL: URL,
        apiKey: String,
        model: String,
        id: String = "gemini-api",
        displayName: String = "Gemini API",
        urlSession: URLSession = .shared,
        requestBuilder: any GeminiDraftRequestBuilding = GeminiDraftRequestBuilder()
    ) {
        self.endpointURL = endpointURL
        self.apiKey = apiKey
        self.model = model
        self.id = id
        self.displayName = displayName
        self.urlSession = urlSession
        self.requestBuilder = requestBuilder
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
        let request = requestBuilder.makeRequest(input: input, categories: categories, options: effectiveOptions)

        var urlRequest = URLRequest(url: endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await urlSession.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HostedDraftProviderError.invalidHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HostedDraftProviderError.httpStatus(httpResponse.statusCode)
        }

        let decoded = try decoder.decode(GeminiGenerateContentResponse.self, from: data)
        let content = decoded.candidates
            .flatMap(\.content.parts)
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw HostedDraftProviderError.missingAssistantContent
        }

        return try TaskDraftParser.parse(
            content,
            captureItemId: input.captureItemId,
            generatedByProvider: "\(id):\(model)"
        )
    }
}

public final class OpenRouterDraftProvider: TaskDraftProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String
    public let mode: ProviderMode = .openRouter
    private let provider: OpenAICompatibleDraftProvider

    public init(
        baseURL: URL = URL(string: "https://openrouter.ai/api/v1")!,
        apiKey: String,
        model: String,
        id: String = "openrouter",
        displayName: String = "OpenRouter",
        urlSession: URLSession = .shared
    ) {
        self.id = id
        self.displayName = displayName
        self.provider = OpenAICompatibleDraftProvider(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            id: id,
            displayName: displayName,
            mode: .openRouter,
            urlSession: urlSession
        )
    }

    public func generateDraft(
        input: TaskDraftInput,
        categories: [LisdoCore.Category],
        options: TaskDraftProviderOptions
    ) async throws -> ProcessingDraft {
        try await provider.generateDraft(input: input, categories: categories, options: options)
    }
}

public final class MiniMaxDraftProvider: TaskDraftProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String
    public let mode: ProviderMode = .minimax
    private let provider: OpenAICompatibleDraftProvider

    public init(
        baseURL: URL = URL(string: "https://api.minimax.io/v1")!,
        apiKey: String,
        model: String,
        id: String = "minimax",
        displayName: String = "MiniMax",
        urlSession: URLSession = .shared,
        requestBuilder: any OpenAICompatibleDraftRequestBuilding = MiniMaxOpenAICompatibleDraftRequestBuilder()
    ) {
        self.id = id
        self.displayName = displayName
        self.provider = OpenAICompatibleDraftProvider(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            id: id,
            displayName: displayName,
            mode: .minimax,
            urlSession: urlSession,
            requestBuilder: requestBuilder,
            contentParsingMode: .miniMax
        )
    }

    public func generateDraft(
        input: TaskDraftInput,
        categories: [LisdoCore.Category],
        options: TaskDraftProviderOptions
    ) async throws -> ProcessingDraft {
        try await provider.generateDraft(input: input, categories: categories, options: options)
    }
}

public final class OllamaDraftProvider: TaskDraftProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String
    public let mode: ProviderMode = .ollama
    private let provider: OpenAICompatibleDraftProvider

    public init(
        baseURL: URL = URL(string: "http://localhost:11434/v1")!,
        model: String,
        id: String = "ollama",
        displayName: String = "Ollama",
        urlSession: URLSession = .shared
    ) {
        self.id = id
        self.displayName = displayName
        self.provider = OpenAICompatibleDraftProvider(
            baseURL: baseURL,
            apiKey: nil,
            model: model,
            id: id,
            displayName: displayName,
            mode: .ollama,
            urlSession: urlSession
        )
    }

    public func generateDraft(
        input: TaskDraftInput,
        categories: [LisdoCore.Category],
        options: TaskDraftProviderOptions
    ) async throws -> ProcessingDraft {
        try await provider.generateDraft(input: input, categories: categories, options: options)
    }
}

public final class LMStudioDraftProvider: TaskDraftProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String
    public let mode: ProviderMode = .lmStudio
    private let provider: OpenAICompatibleDraftProvider

    public init(
        baseURL: URL = URL(string: "http://localhost:1234/v1")!,
        model: String,
        id: String = "lm-studio",
        displayName: String = "LM Studio",
        urlSession: URLSession = .shared
    ) {
        self.id = id
        self.displayName = displayName
        self.provider = OpenAICompatibleDraftProvider(
            baseURL: baseURL,
            apiKey: nil,
            model: model,
            id: id,
            displayName: displayName,
            mode: .lmStudio,
            urlSession: urlSession
        )
    }

    public func generateDraft(
        input: TaskDraftInput,
        categories: [LisdoCore.Category],
        options: TaskDraftProviderOptions
    ) async throws -> ProcessingDraft {
        try await provider.generateDraft(input: input, categories: categories, options: options)
    }
}

public final class LocalOpenAICompatibleDraftProvider: TaskDraftProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String
    public let mode: ProviderMode = .localModel
    private let provider: OpenAICompatibleDraftProvider

    public init(
        baseURL: URL,
        apiKey: String? = nil,
        model: String,
        id: String = "local-openai-compatible",
        displayName: String = "Local OpenAI-compatible Model",
        urlSession: URLSession = .shared
    ) {
        self.id = id
        self.displayName = displayName
        self.provider = OpenAICompatibleDraftProvider(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            id: id,
            displayName: displayName,
            mode: .localModel,
            urlSession: urlSession
        )
    }

    public func generateDraft(
        input: TaskDraftInput,
        categories: [LisdoCore.Category],
        options: TaskDraftProviderOptions
    ) async throws -> ProcessingDraft {
        try await provider.generateDraft(input: input, categories: categories, options: options)
    }
}

private struct AnthropicMessagesResponse: Decodable {
    let content: [ContentBlock]

    struct ContentBlock: Decodable {
        let type: String?
        let text: String?
    }
}

private struct GeminiGenerateContentResponse: Decodable {
    let candidates: [Candidate]

    struct Candidate: Decodable {
        let content: Content
    }

    struct Content: Decodable {
        let parts: [Part]
    }

    struct Part: Decodable {
        let text: String?
    }
}
