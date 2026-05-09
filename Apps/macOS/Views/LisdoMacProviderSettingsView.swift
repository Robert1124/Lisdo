import LisdoCore
import SwiftUI

struct LisdoMacProviderSettingsView: View {
    private let credentialStore = KeychainCredentialStore()
    private let preferenceStore = LisdoLocalProviderPreferenceStore()
    private let factory = DraftProviderFactory()

    @State private var endpoint = ""
    @State private var model = ""
    @State private var displayName = ""
    @State private var apiKey = ""
    @State private var status = "Provider settings are local to this Mac."
    @State private var providerStatus = "Provider choice is local to this Mac."
    @State private var providerMode: ProviderMode = .openAICompatibleBYOK
    @State private var providerSelection: ProviderPickerSelection = .addMore
    @State private var editingMode: ProviderMode = .openAICompatibleBYOK
    @State private var cliKind: CLIProviderKind = .codex
    @State private var cliExecutablePath = ""
    @State private var cliTimeoutSeconds = 120.0
    @State private var cliStatus = "No Mac-only CLI settings saved on this Mac."
    @AppStorage(LisdoCaptureModePreferences.imageProcessingModeKey)
    private var imageProcessingModeRawValue = LisdoImageProcessingMode.directLLM.rawValue
    @AppStorage(LisdoCaptureModePreferences.voiceProcessingModeKey)
    private var voiceProcessingModeRawValue = LisdoVoiceProcessingMode.directLLM.rawValue

    var body: some View {
        Form {
            Section {
                LisdoSettingsPillToggle(
                    title: "Image input",
                    selection: $imageProcessingModeRawValue,
                    options: LisdoImageProcessingMode.allCases,
                    label: \.displayName
                )

                Text(selectedImageProcessingMode.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LisdoSettingsPillToggle(
                    title: "Voice input",
                    selection: $voiceProcessingModeRawValue,
                    options: LisdoVoiceProcessingMode.allCases,
                    label: \.displayName
                )

                Text(selectedVoiceProcessingMode.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Capture input")
            } footer: {
                Text("Direct image/audio modes depend on the selected provider supporting those attachment types. Output still lands as a draft for review.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Provider", selection: $providerSelection) {
                    ForEach(configuredProviderModes, id: \.self) { mode in
                        Text(providerDisplayName(for: mode)).tag(ProviderPickerSelection.provider(mode))
                    }
                    Text("Add More Provider").tag(ProviderPickerSelection.addMore)
                }
                .pickerStyle(.menu)
                .onChange(of: providerSelection) { _, newSelection in
                    selectProvider(newSelection)
                }

                Text("Direct Mac captures and pending queue processing use this selected provider only. If it is unavailable or fails, the capture is marked failed for review. Provider choice is local and AI output remains a reviewable draft.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(providerStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Provider")
            } footer: {
                Text("This preference is not stored in SwiftData and does not sync through iCloud.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Format", selection: $editingMode) {
                    ForEach(DraftProviderFactory.supportedModes, id: \.self) { mode in
                        Text(DraftProviderFactory.metadata(for: mode).displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: editingMode) { _, _ in
                    loadProviderFields()
                }

                if editingMode == .macOnlyCLI {
                    cliFields
                } else {
                    TextField("Display name", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Endpoint", text: $endpoint)
                        .textFieldStyle(.roundedBorder)
                    TextField("Model", text: $model)
                        .textFieldStyle(.roundedBorder)

                    if metadata.requiresAPIKey || editingMode == .localModel {
                        SecureField(apiKeyPlaceholder, text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(providerFormatHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button {
                        save()
                    } label: {
                        Label("Save", systemImage: "key")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) {
                        removeProvider(editingMode)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .disabled(!isProviderConfigured(editingMode))
                }
            } header: {
                Text("Provider configuration")
            } footer: {
                Text("API keys are stored in this Mac's Keychain. Endpoints, models, display names, and CLI paths stay in local UserDefaults. None of these provider secrets are synced through iCloud.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Text(cliStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Mac-only CLI status")
            } footer: {
                Text("Lisdo passes captured text to the selected CLI and accepts only strict draft JSON. Executable paths stay local on this Mac and are not synced.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .navigationTitle("Settings")
        .onAppear(perform: load)
    }

    private var metadata: DraftProviderModeMetadata {
        DraftProviderFactory.metadata(for: editingMode)
    }

    private var configuredProviderModes: [ProviderMode] {
        DraftProviderFactory.supportedModes.filter(isProviderConfigured)
    }

    private var apiKeyPlaceholder: String {
        metadata.requiresAPIKey ? "API key" : "Optional API key"
    }

    private var selectedImageProcessingMode: LisdoImageProcessingMode {
        LisdoImageProcessingMode(rawValue: imageProcessingModeRawValue) ?? .visionOCR
    }

    private var selectedVoiceProcessingMode: LisdoVoiceProcessingMode {
        LisdoVoiceProcessingMode(rawValue: voiceProcessingModeRawValue) ?? .speechTranscript
    }

    private var providerFormatHelp: String {
        switch editingMode {
        case .anthropic:
            return "Anthropic-compatible BYOK uses endpoint https://api.anthropic.com/v1/messages, header x-api-key, anthropic-version 2023-06-01, and a Messages API model such as claude-3-5-haiku-latest."
        case .openAICompatibleBYOK, .minimax, .openRouter, .ollama, .lmStudio, .localModel:
            return "OpenAI-compatible formats use a /chat/completions endpoint with Bearer authorization when an API key is configured."
        case .gemini:
            return "Gemini API uses the generateContent endpoint and x-goog-api-key."
        case .macOnlyCLI:
            return "Mac-only CLI providers receive text input and must return strict Lisdo draft JSON."
        }
    }

    private var cliFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("CLI strategy", selection: $cliKind) {
                Text("Codex CLI").tag(CLIProviderKind.codex)
                Text("Claude Code CLI").tag(CLIProviderKind.claudeCode)
                Text("Gemini CLI").tag(CLIProviderKind.gemini)
            }
            .pickerStyle(.menu)

            TextField("Optional executable path", text: $cliExecutablePath)
                .textFieldStyle(.roundedBorder)

            Stepper(value: $cliTimeoutSeconds, in: 15...600, step: 15) {
                Text("Timeout: \(Int(cliTimeoutSeconds)) seconds")
            }
        }
    }

    private func hasSavedKey(for mode: ProviderMode) -> Bool {
        let storedKey: String?
        if mode == .openAICompatibleBYOK {
            storedKey = try? credentialStore.readOpenAICompatibleAPIKey()
        } else {
            storedKey = try? credentialStore.readAPIKey(for: mode)
        }
        return !(storedKey?.lisdoTrimmed ?? "").isEmpty
    }

    private func isProviderConfigured(_ mode: ProviderMode) -> Bool {
        if mode == .macOnlyCLI {
            return preferenceStore.readMacOnlyCLISettings() != nil
        }

        let metadata = DraftProviderFactory.metadata(for: mode)
        if metadata.requiresAPIKey {
            return hasSavedKey(for: mode)
        }

        return credentialStore.readProviderSettings(for: mode) != nil
            || (mode == .openAICompatibleBYOK && credentialStore.readOpenAICompatibleSettings() != nil)
    }

    private func load() {
        let savedProviderMode = preferenceStore.readProviderMode(default: .openAICompatibleBYOK)
        if isProviderConfigured(savedProviderMode) {
            providerMode = savedProviderMode
            providerSelection = .provider(savedProviderMode)
            providerStatus = "\(providerDisplayName(for: savedProviderMode)) is selected."
            editingMode = savedProviderMode
        } else if let firstConfiguredMode = configuredProviderModes.first {
            providerMode = firstConfiguredMode
            providerSelection = .provider(firstConfiguredMode)
            try? preferenceStore.saveProviderMode(firstConfiguredMode)
            providerStatus = "\(providerDisplayName(for: firstConfiguredMode)) is selected."
            editingMode = firstConfiguredMode
        } else {
            providerSelection = .addMore
            providerStatus = "No provider is saved yet. Choose a format below, then click Save."
            editingMode = .openAICompatibleBYOK
        }
        loadProviderFields()

        if let cliSettings = preferenceStore.readMacOnlyCLISettings() {
            cliKind = cliSettings.descriptor.kind
            cliExecutablePath = cliSettings.executablePath ?? ""
            cliTimeoutSeconds = cliSettings.descriptor.defaultTimeoutSeconds
            cliStatus = "\(cliSettings.descriptor.displayName) strategy is saved locally."
        }
    }

    private func selectProvider(_ selection: ProviderPickerSelection) {
        switch selection {
        case .provider(let mode):
            do {
                try preferenceStore.saveProviderMode(mode)
                providerMode = mode
                providerStatus = "\(providerDisplayName(for: mode)) is selected."
                editingMode = mode
                loadProviderFields()
            } catch {
                providerStatus = "Could not save provider: \(error.localizedDescription)"
            }
        case .addMore:
            providerStatus = "Choose a provider format below, configure it, then click Save."
            if configuredProviderModes.contains(editingMode) {
                editingMode = firstUnconfiguredMode ?? .openAICompatibleBYOK
                loadProviderFields()
            }
        }
    }

    private var firstUnconfiguredMode: ProviderMode? {
        DraftProviderFactory.supportedModes.first { !isProviderConfigured($0) }
    }

    private func loadProviderFields() {
        let settings = factory.loadSettings(for: editingMode)
        endpoint = settings.endpointURL?.absoluteString ?? ""
        model = settings.model
        displayName = settings.displayName ?? metadata.displayName
        apiKey = ""

        if editingMode == .macOnlyCLI {
            status = "Configure the CLI strategy below, then save provider settings."
        } else if metadata.requiresAPIKey {
            status = hasSavedKey(for: editingMode)
                ? "\(metadata.displayName) API key is saved locally in Keychain."
                : "\(metadata.displayName) needs an API key before it can create drafts."
        } else {
            status = "\(metadata.displayName) uses a local endpoint. Add an optional key only if your server requires one."
        }
    }

    private func save() {
        do {
            if editingMode == .macOnlyCLI {
                try preferenceStore.saveMacOnlyCLISettings(
                    MacOnlyCLILocalSettings(
                        descriptor: cliDescriptor(kind: cliKind, timeoutSeconds: cliTimeoutSeconds),
                        executablePath: cliExecutablePath
                    )
                )
                cliStatus = "\(cliDisplayName(cliKind)) strategy saved locally. Timeout \(Int(cliTimeoutSeconds)) seconds."
                status = "Mac-only CLI settings saved. Captures still become drafts for review."
            } else {
                let trimmedEndpoint = endpoint.lisdoTrimmed
                guard let endpointURL = URL(string: trimmedEndpoint) else {
                    status = "Enter a valid endpoint URL."
                    return
                }

                if metadata.requiresAPIKey && apiKey.lisdoTrimmed.isEmpty && !hasSavedKey(for: editingMode) {
                    status = "Add an API key before saving this provider."
                    return
                }

                let settings = DraftProviderLocalSettings(
                    mode: editingMode,
                    endpointURL: endpointURL,
                    model: model.lisdoTrimmed.isEmpty ? metadata.defaultModel : model.lisdoTrimmed,
                    displayName: displayName.lisdoTrimmed.isEmpty ? metadata.displayName : displayName.lisdoTrimmed,
                    requiresAPIKey: metadata.requiresAPIKey
                )
                try credentialStore.saveProviderSettings(settings)

                if editingMode == .openAICompatibleBYOK {
                    try credentialStore.saveOpenAICompatibleSettings(endpointURL: endpointURL, model: settings.model)
                }

                if !apiKey.lisdoTrimmed.isEmpty {
                    if editingMode == .openAICompatibleBYOK {
                        try credentialStore.saveOpenAICompatibleAPIKey(apiKey.lisdoTrimmed)
                    }
                    try credentialStore.saveAPIKey(apiKey.lisdoTrimmed, for: editingMode)
                    apiKey = ""
                    status = "\(settings.displayName ?? metadata.displayName) saved. API key is local-only in Keychain."
                } else if metadata.requiresAPIKey && !hasSavedKey(for: editingMode) {
                    status = "\(settings.displayName ?? metadata.displayName) endpoint and model saved. Add an API key before this provider can create drafts."
                } else {
                    status = "\(settings.displayName ?? metadata.displayName) settings saved."
                }
            }

            try preferenceStore.saveProviderMode(editingMode)
            providerMode = editingMode
            providerSelection = .provider(editingMode)
            providerStatus = "\(providerDisplayName(for: editingMode)) is selected."
        } catch {
            status = "Could not save provider settings: \(error.localizedDescription)"
        }
    }

    private func removeProvider(_ mode: ProviderMode) {
        let removedDisplayName = providerDisplayName(for: mode)

        do {
            if mode == .openAICompatibleBYOK {
                try credentialStore.deleteOpenAICompatibleCredentialsAndSettings()
                try credentialStore.deleteProviderCredentialsAndSettings(for: mode)
            } else if mode == .macOnlyCLI {
                preferenceStore.deleteMacOnlyCLISettings()
            } else {
                try credentialStore.deleteProviderCredentialsAndSettings(for: mode)
            }

            apiKey = ""
            status = "\(removedDisplayName) removed from this Mac."
            cliStatus = preferenceStore.readMacOnlyCLISettings() == nil
                ? "No Mac-only CLI settings saved on this Mac."
                : cliStatus
            reconcileProviderAfterRemoval(removedMode: mode)
            loadProviderFields()
        } catch {
            status = "Could not remove provider: \(error.localizedDescription)"
        }
    }

    private func reconcileProviderAfterRemoval(removedMode: ProviderMode) {
        guard providerMode == removedMode else { return }

        if let nextMode = configuredProviderModes.first {
            providerMode = nextMode
            providerSelection = .provider(nextMode)
            try? preferenceStore.saveProviderMode(nextMode)
            providerStatus = "\(providerDisplayName(for: nextMode)) is selected."
        } else {
            preferenceStore.deleteProviderMode()
            providerSelection = .addMore
            providerStatus = "No provider is saved yet. Choose a format below, then click Save."
        }
    }

    private func providerDisplayName(for mode: ProviderMode) -> String {
        let savedName = factory.loadSettings(for: mode).displayName?.lisdoTrimmed
        if let savedName, !savedName.isEmpty {
            return savedName
        }
        return DraftProviderFactory.metadata(for: mode).displayName
    }

    private func cliDescriptor(kind: CLIProviderKind, timeoutSeconds: TimeInterval) -> CLIDraftProviderDescriptor {
        switch kind {
        case .codex:
            return .codex(defaultTimeoutSeconds: timeoutSeconds)
        case .claudeCode:
            return .claudeCode(defaultTimeoutSeconds: timeoutSeconds)
        case .gemini:
            return .gemini(defaultTimeoutSeconds: timeoutSeconds)
        }
    }

    private func cliDisplayName(_ kind: CLIProviderKind) -> String {
        switch kind {
        case .codex:
            return "Codex CLI"
        case .claudeCode:
            return "Claude Code CLI"
        case .gemini:
            return "Gemini CLI"
        }
    }
}

private enum ProviderPickerSelection: Hashable {
    case provider(ProviderMode)
    case addMore
}

private struct LisdoSettingsPillToggle<Option>: View where Option: CaseIterable & Identifiable & RawRepresentable, Option.RawValue == String {
    let title: String
    @Binding var selection: String
    let options: [Option]
    let label: KeyPath<Option, String>

    @Namespace private var selectionNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.callout.weight(.semibold))

            HStack(spacing: 0) {
                ForEach(options) { option in
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            selection = option.rawValue
                        }
                    } label: {
                        Text(option[keyPath: label])
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .foregroundStyle(isSelected(option) ? LisdoMacTheme.ink1 : LisdoMacTheme.ink3)
                            .background {
                                if isSelected(option) {
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .fill(LisdoMacTheme.info.opacity(0.18))
                                        .matchedGeometryEffect(id: "selected-\(title)", in: selectionNamespace)
                                        .lisdoGlassSurface(
                                            cornerRadius: 15,
                                            tint: LisdoMacTheme.info.opacity(0.16),
                                            interactive: true
                                        )
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option[keyPath: label])
                    .accessibilityAddTraits(isSelected(option) ? [.isSelected] : [])
                }
            }
            .padding(4)
            .lisdoGlassSurface(cornerRadius: 19, interactive: true)
        }
    }

    private func isSelected(_ option: Option) -> Bool {
        selection == option.rawValue
    }
}
