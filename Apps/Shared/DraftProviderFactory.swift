import Foundation
import LisdoCore

public struct DraftProviderModeMetadata: Equatable, Sendable {
    public var mode: ProviderMode
    public var displayName: String
    public var defaultEndpointURL: URL?
    public var defaultModel: String
    public var requiresAPIKey: Bool
    public var isNormallyMacLocal: Bool

    public init(
        mode: ProviderMode,
        displayName: String,
        defaultEndpointURL: URL?,
        defaultModel: String,
        requiresAPIKey: Bool,
        isNormallyMacLocal: Bool
    ) {
        self.mode = mode
        self.displayName = displayName
        self.defaultEndpointURL = defaultEndpointURL
        self.defaultModel = defaultModel
        self.requiresAPIKey = requiresAPIKey
        self.isNormallyMacLocal = isNormallyMacLocal
    }
}

public enum DraftProviderFactoryError: Error, Equatable, Sendable {
    case unsupportedProviderMode(ProviderMode)
    case missingMacOnlyCLIBuilder
}

public final class DraftProviderFactory: @unchecked Sendable {
    public typealias MacOnlyCLIProviderBuilder = @Sendable (MacOnlyCLILocalSettings) throws -> any TaskDraftProvider

    private let credentialStore: KeychainCredentialStore
    private let preferenceStore: LisdoLocalProviderPreferenceStore
    private let urlSession: URLSession
    private let macOnlyCLIProviderBuilder: MacOnlyCLIProviderBuilder?

    public init(
        credentialStore: KeychainCredentialStore = KeychainCredentialStore(),
        preferenceStore: LisdoLocalProviderPreferenceStore = LisdoLocalProviderPreferenceStore(),
        urlSession: URLSession = .shared,
        macOnlyCLIProviderBuilder: MacOnlyCLIProviderBuilder? = nil
    ) {
        self.credentialStore = credentialStore
        self.preferenceStore = preferenceStore
        self.urlSession = urlSession
        self.macOnlyCLIProviderBuilder = macOnlyCLIProviderBuilder
    }

    public static var supportedModes: [ProviderMode] {
        [
            .openAICompatibleBYOK,
            .minimax,
            .anthropic,
            .gemini,
            .openRouter,
            .ollama,
            .lmStudio,
            .localModel,
            .macOnlyCLI
        ]
    }

    public static func metadata(for mode: ProviderMode) -> DraftProviderModeMetadata {
        switch mode {
        case .openAICompatibleBYOK:
            return DraftProviderModeMetadata(
                mode: mode,
                displayName: "OpenAI-compatible BYOK",
                defaultEndpointURL: URL(string: "https://api.openai.com/v1"),
                defaultModel: "gpt-4.1-mini",
                requiresAPIKey: true,
                isNormallyMacLocal: false
            )
        case .anthropic:
            return DraftProviderModeMetadata(
                mode: mode,
                displayName: "Anthropic-compatible BYOK",
                defaultEndpointURL: URL(string: "https://api.anthropic.com/v1/messages"),
                defaultModel: "claude-3-5-haiku-latest",
                requiresAPIKey: true,
                isNormallyMacLocal: false
            )
        case .minimax:
            return DraftProviderModeMetadata(
                mode: mode,
                displayName: "MiniMax",
                defaultEndpointURL: URL(string: "https://api.minimax.io/v1"),
                defaultModel: "MiniMax-M2.7",
                requiresAPIKey: true,
                isNormallyMacLocal: false
            )
        case .gemini:
            return DraftProviderModeMetadata(
                mode: mode,
                displayName: "Gemini API",
                defaultEndpointURL: URL(string: "https://generativelanguage.googleapis.com/v1beta"),
                defaultModel: "gemini-1.5-flash",
                requiresAPIKey: true,
                isNormallyMacLocal: false
            )
        case .openRouter:
            return DraftProviderModeMetadata(
                mode: mode,
                displayName: "OpenRouter",
                defaultEndpointURL: URL(string: "https://openrouter.ai/api/v1"),
                defaultModel: "openai/gpt-4.1-mini",
                requiresAPIKey: true,
                isNormallyMacLocal: false
            )
        case .ollama:
            return DraftProviderModeMetadata(
                mode: mode,
                displayName: "Ollama",
                defaultEndpointURL: URL(string: "http://localhost:11434/v1"),
                defaultModel: "llama3.2",
                requiresAPIKey: false,
                isNormallyMacLocal: true
            )
        case .lmStudio:
            return DraftProviderModeMetadata(
                mode: mode,
                displayName: "LM Studio",
                defaultEndpointURL: URL(string: "http://localhost:1234/v1"),
                defaultModel: "local-model",
                requiresAPIKey: false,
                isNormallyMacLocal: true
            )
        case .localModel:
            return DraftProviderModeMetadata(
                mode: mode,
                displayName: "Local Model",
                defaultEndpointURL: URL(string: "http://localhost:8000/v1"),
                defaultModel: "local-model",
                requiresAPIKey: false,
                isNormallyMacLocal: true
            )
        case .macOnlyCLI:
            return DraftProviderModeMetadata(
                mode: mode,
                displayName: "Mac-only CLI",
                defaultEndpointURL: nil,
                defaultModel: CLIDraftProviderDescriptor.codex().displayName,
                requiresAPIKey: false,
                isNormallyMacLocal: true
            )
        }
    }

    public func metadata(for mode: ProviderMode) -> DraftProviderModeMetadata {
        Self.metadata(for: mode)
    }

    public static func defaultSettings(for mode: ProviderMode) -> DraftProviderLocalSettings {
        let metadata = Self.metadata(for: mode)
        return DraftProviderLocalSettings(
            mode: mode,
            endpointURL: metadata.defaultEndpointURL,
            model: metadata.defaultModel,
            displayName: metadata.displayName,
            requiresAPIKey: metadata.requiresAPIKey
        )
    }

    public func defaultSettings(for mode: ProviderMode) -> DraftProviderLocalSettings {
        Self.defaultSettings(for: mode)
    }

    public func loadSettings(for mode: ProviderMode) -> DraftProviderLocalSettings {
        if mode == .openAICompatibleBYOK,
           let legacySettings = credentialStore.readOpenAICompatibleSettings()
        {
            return DraftProviderLocalSettings(
                mode: mode,
                endpointURL: legacySettings.endpointURL,
                model: legacySettings.model,
                displayName: Self.metadata(for: mode).displayName,
                requiresAPIKey: true
            )
        }

        return credentialStore.readProviderSettings(for: mode) ?? Self.defaultSettings(for: mode)
    }

    public func makePreferredProvider() throws -> (any TaskDraftProvider)? {
        try makeProvider(for: preferenceStore.readProviderMode())
    }

    public func makeProvider(for mode: ProviderMode) throws -> (any TaskDraftProvider)? {
        switch mode {
        case .openAICompatibleBYOK:
            let settings = loadSettings(for: mode)
            guard let endpointURL = settings.endpointURL,
                  let apiKey = try readAPIKey(for: mode),
                  !apiKey.trimmedForDraftProviderFactory.isEmpty
            else {
                return nil
            }

            let requestBuilder = Self.openAICompatibleRequestBuilder(endpointURL: endpointURL, model: settings.model)
            return OpenAICompatibleDraftProvider(
                baseURL: endpointURL,
                apiKey: apiKey,
                model: settings.model,
                displayName: settings.displayName ?? Self.metadata(for: mode).displayName,
                mode: mode,
                urlSession: urlSession,
                requestBuilder: requestBuilder
            )

        case .anthropic:
            let settings = loadSettings(for: mode)
            guard let endpointURL = settings.endpointURL,
                  let apiKey = try readAPIKey(for: mode),
                  !apiKey.trimmedForDraftProviderFactory.isEmpty
            else {
                return nil
            }

            return AnthropicDraftProvider(
                endpointURL: endpointURL,
                apiKey: apiKey,
                model: settings.model,
                displayName: settings.displayName ?? Self.metadata(for: mode).displayName,
                urlSession: urlSession
            )

        case .minimax:
            let settings = loadSettings(for: mode)
            guard let endpointURL = settings.endpointURL,
                  let apiKey = try readAPIKey(for: mode),
                  !apiKey.trimmedForDraftProviderFactory.isEmpty
            else {
                return nil
            }

            return MiniMaxDraftProvider(
                baseURL: endpointURL,
                apiKey: apiKey,
                model: settings.model,
                displayName: settings.displayName ?? Self.metadata(for: mode).displayName,
                urlSession: urlSession
            )

        case .gemini:
            let settings = loadSettings(for: mode)
            guard let endpointURL = settings.endpointURL,
                  let apiKey = try readAPIKey(for: mode),
                  !apiKey.trimmedForDraftProviderFactory.isEmpty
            else {
                return nil
            }

            return GeminiAPIDraftProvider(
                baseURL: endpointURL,
                apiKey: apiKey,
                model: settings.model,
                displayName: settings.displayName ?? Self.metadata(for: mode).displayName,
                urlSession: urlSession
            )

        case .openRouter:
            let settings = loadSettings(for: mode)
            guard let endpointURL = settings.endpointURL,
                  let apiKey = try readAPIKey(for: mode),
                  !apiKey.trimmedForDraftProviderFactory.isEmpty
            else {
                return nil
            }

            return OpenRouterDraftProvider(
                baseURL: endpointURL,
                apiKey: apiKey,
                model: settings.model,
                displayName: settings.displayName ?? Self.metadata(for: mode).displayName,
                urlSession: urlSession
            )

        case .ollama:
            let settings = loadSettings(for: mode)
            guard let endpointURL = settings.endpointURL else {
                return nil
            }

            return OllamaDraftProvider(
                baseURL: endpointURL,
                model: settings.model,
                displayName: settings.displayName ?? Self.metadata(for: mode).displayName,
                urlSession: urlSession
            )

        case .lmStudio:
            let settings = loadSettings(for: mode)
            guard let endpointURL = settings.endpointURL else {
                return nil
            }

            return LMStudioDraftProvider(
                baseURL: endpointURL,
                model: settings.model,
                displayName: settings.displayName ?? Self.metadata(for: mode).displayName,
                urlSession: urlSession
            )

        case .localModel:
            let settings = loadSettings(for: mode)
            guard let endpointURL = settings.endpointURL else {
                return nil
            }

            let apiKey = try readAPIKey(for: mode)
            return LocalOpenAICompatibleDraftProvider(
                baseURL: endpointURL,
                apiKey: apiKey,
                model: settings.model,
                displayName: settings.displayName ?? Self.metadata(for: mode).displayName,
                urlSession: urlSession
            )

        case .macOnlyCLI:
            guard let builder = macOnlyCLIProviderBuilder else {
                return nil
            }
            guard let settings = preferenceStore.readMacOnlyCLISettings() else {
                return nil
            }

            return try builder(settings)
        }
    }

    private func readAPIKey(for mode: ProviderMode) throws -> String? {
        if mode == .openAICompatibleBYOK {
            return try credentialStore.readOpenAICompatibleAPIKey() ?? credentialStore.readAPIKey(for: mode)
        }

        return try credentialStore.readAPIKey(for: mode)
    }

    private static func openAICompatibleRequestBuilder(
        endpointURL: URL,
        model: String
    ) -> any OpenAICompatibleDraftRequestBuilding {
        if indicatesMiniMax(endpointURL: endpointURL, model: model) {
            return MiniMaxOpenAICompatibleDraftRequestBuilder()
        }

        return OpenAICompatibleDraftRequestBuilder()
    }

    private static func indicatesMiniMax(endpointURL: URL, model: String) -> Bool {
        let host = endpointURL.host?.lowercased() ?? ""
        return host.contains("minimax") || model.lowercased().contains("minimax")
    }
}

private extension String {
    var trimmedForDraftProviderFactory: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
