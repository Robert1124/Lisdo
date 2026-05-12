import LisdoCore
import SwiftData
import SwiftUI

struct LisdoMacProviderSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sparkleUpdater: LisdoMacSparkleUpdater
    @Query(sort: \LisdoSyncedSettings.updatedAt, order: .reverse) private var syncedSettings: [LisdoSyncedSettings]

    private let credentialStore = KeychainCredentialStore()
    private let preferenceStore = LisdoLocalProviderPreferenceStore()
    private let factory = DraftProviderFactory()

    @State private var endpoint = ""
    @State private var model = ""
    @State private var displayName = ""
    @State private var apiKey = ""
    @State private var status = ""
    @State private var providerStatus = ""
    @State private var providerMode: ProviderMode = .openAICompatibleBYOK
    @State private var providerSelection: ProviderPickerSelection = .addMore
    @State private var editingMode: ProviderMode = .openAICompatibleBYOK
    @State private var cliKind: CLIProviderKind = .codex
    @State private var cliExecutablePath = ""
    @State private var cliTimeoutSeconds = 120.0
    @State private var cliStatus = ""
    @State private var imageProcessingModeRawValue = LisdoSyncedSettings.defaultImageProcessingModeRawValue
    @State private var voiceProcessingModeRawValue = LisdoSyncedSettings.defaultVoiceProcessingModeRawValue
    @State private var isApplyingSyncedSettings = false
    @State private var selectedSettingsTab: LisdoMacSettingsTab = .capture
    @AppStorage(LisdoMacHotKeyPreferences.quickCapturePresetDefaultsKey) private var quickCaptureHotKeyPresetId = LisdoMacHotKeyPreferences.defaultQuickCapturePresetId
    @AppStorage(LisdoMacHotKeyPreferences.selectedAreaPresetDefaultsKey) private var selectedAreaHotKeyPresetId = LisdoMacHotKeyPreferences.defaultSelectedAreaPresetId
    @AppStorage(LisdoMacNotifications.hotKeyStatusDefaultsKey) private var hotKeyStatus = "Global hotkeys are not registered yet."

    var body: some View {
        VStack(spacing: 0) {
            settingsTabBar

            Divider()
                .opacity(0.55)

            selectedSettingsContent
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 520, minHeight: 540)
        .background(LisdoMacTheme.surface)
        .onAppear(perform: load)
        .onChange(of: syncedSettingsSnapshot) { _, _ in
            loadSyncedSelections(updateEditingMode: false)
        }
    }

    private var settingsTabBar: some View {
        HStack(spacing: 8) {
            ForEach(LisdoMacSettingsTab.allCases) { tab in
                Button {
                    selectedSettingsTab = tab
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                        .labelStyle(.titleAndIcon)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(selectedSettingsTab == tab ? LisdoMacTheme.ink1 : LisdoMacTheme.ink3)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(
                            selectedSettingsTab == tab ? LisdoMacTheme.surface3 : Color.clear,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .focusable(false)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var selectedSettingsContent: some View {
        switch selectedSettingsTab {
        case .capture:
            captureSettingsTab
        case .provider:
            providerSettingsTab
        case .hotkeys:
            hotKeySettingsTab
        case .about:
            aboutSettingsTab
        }
    }

    private var captureSettingsTab: some View {
        Form {
            Section {
                LisdoSettingsPillToggle(
                    title: "Image input",
                    selection: $imageProcessingModeRawValue,
                    options: LisdoImageProcessingMode.allCases,
                    label: \.displayName
                )
                .onChange(of: imageProcessingModeRawValue) { _, newValue in
                    saveImageProcessingModeRawValue(newValue)
                }

                Label("Voice uses transcript first", systemImage: "text.bubble")
                    .font(.callout.weight(.medium))
            } header: {
                Text("Capture input")
            }
        }
        .formStyle(.grouped)
    }

    private var providerSettingsTab: some View {
        Form {
            Section {
                Picker("Provider", selection: $providerSelection) {
                    ForEach(configuredProviderModes, id: \.self) { mode in
                        Text(providerDisplayName(for: mode)).tag(ProviderPickerSelection.provider(mode))
                    }
                    Text("Add More Provider").tag(ProviderPickerSelection.addMore)
                }
                .pickerStyle(.menu)
                .onChange(of: providerSelection) { _, newSelection in
                    guard !isApplyingSyncedSettings else { return }
                    selectProvider(newSelection)
                }

                if !providerStatus.isEmpty {
                    Text(providerStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Provider")
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

                if !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
            }

            if !cliStatus.isEmpty {
                Section {
                    Text(cliStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Mac-only CLI status")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var hotKeySettingsTab: some View {
        Form {
            Section {
                Picker("Quick capture", selection: $quickCaptureHotKeyPresetId) {
                    ForEach(LisdoMacHotKeyPreferences.quickCapturePresets) { preset in
                        Text(preset.title).tag(preset.id)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: quickCaptureHotKeyPresetId) { _, _ in
                    notifyHotKeySettingsChanged()
                }

                Picker("Selected area", selection: $selectedAreaHotKeyPresetId) {
                    ForEach(LisdoMacHotKeyPreferences.selectedAreaPresets) { preset in
                        Text(preset.title).tag(preset.id)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedAreaHotKeyPresetId) { _, _ in
                    notifyHotKeySettingsChanged()
                }

                Button {
                    quickCaptureHotKeyPresetId = LisdoMacHotKeyPreferences.defaultQuickCapturePresetId
                    selectedAreaHotKeyPresetId = LisdoMacHotKeyPreferences.defaultSelectedAreaPresetId
                    notifyHotKeySettingsChanged()
                } label: {
                    Label("Restore defaults", systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text("Global hotkeys")
            }
        }
        .formStyle(.grouped)
    }

    private var aboutSettingsTab: some View {
        Form {
            Section {
                LabeledContent("Version") {
                    Text(versionInfo.shortVersion)
                }

                LabeledContent("Build") {
                    Text(versionInfo.buildVersion)
                }

                LabeledContent("Update feed") {
                    Text(versionInfo.appcastURL.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } header: {
                Text("Lisdo")
            }

            Section {
                Text(sparkleUpdater.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button {
                        sparkleUpdater.checkForUpdates()
                    } label: {
                        Label("Check for updates", systemImage: "arrow.clockwise")
                    }
                    .disabled(!sparkleUpdater.canCheckForUpdates)

                    Link("Release notes", destination: versionInfo.updatesPageURL)
                }
            } header: {
                Text("Updates")
            }
        }
        .formStyle(.grouped)
    }

    private var metadata: DraftProviderModeMetadata {
        DraftProviderFactory.metadata(for: editingMode)
    }

    private var versionInfo: LisdoMacVersionInfo {
        .current
    }

    private var syncedSettingsStore: LisdoSyncedSettingsStore {
        LisdoSyncedSettingsStore(context: modelContext)
    }

    private var syncedSettingsSnapshot: String {
        guard let settings = syncedSettings.first else {
            return "missing"
        }

        return [
            settings.selectedProviderMode.rawValue,
            settings.imageProcessingModeRawValue,
            settings.voiceProcessingModeRawValue,
            String(settings.updatedAt.timeIntervalSinceReferenceDate)
        ].joined(separator: "|")
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
        loadSyncedSelections(updateEditingMode: true)

        if let cliSettings = preferenceStore.readMacOnlyCLISettings() {
            cliKind = cliSettings.descriptor.kind
            cliExecutablePath = cliSettings.executablePath ?? ""
            cliTimeoutSeconds = cliSettings.descriptor.defaultTimeoutSeconds
            cliStatus = "\(cliSettings.descriptor.displayName) strategy is saved locally."
        }
    }

    private func loadSyncedSelections(updateEditingMode: Bool) {
        do {
            let settings = try syncedSettingsStore.fetchOrCreateSettings()
            applySyncedSettings(settings, updateEditingMode: updateEditingMode)
        } catch {
            providerStatus = "Could not load synced product settings: \(error.localizedDescription)"
            if updateEditingMode {
                loadProviderFields()
            }
        }
    }

    private func applySyncedSettings(_ settings: LisdoSyncedSettings, updateEditingMode: Bool) {
        let previousSelectedMode = providerMode
        let previousEditingMode = editingMode

        isApplyingSyncedSettings = true
        defer { isApplyingSyncedSettings = false }

        providerMode = settings.selectedProviderMode
        imageProcessingModeRawValue = settings.imageProcessingModeRawValue
        voiceProcessingModeRawValue = settings.voiceProcessingModeRawValue

        if isProviderConfigured(settings.selectedProviderMode) {
            providerSelection = .provider(settings.selectedProviderMode)
            providerStatus = ""
        } else {
            providerSelection = .addMore
            providerStatus = ""
        }

        if updateEditingMode || previousEditingMode == previousSelectedMode {
            editingMode = settings.selectedProviderMode
            loadProviderFields()
        }
    }

    private func selectProvider(_ selection: ProviderPickerSelection) {
        switch selection {
        case .provider(let mode):
            do {
                let settings = try syncedSettingsStore.updateProviderMode(mode)
                applySyncedSettings(settings, updateEditingMode: true)
            } catch {
                providerStatus = "Could not save provider: \(error.localizedDescription)"
            }
        case .addMore:
            providerStatus = ""
            if configuredProviderModes.contains(editingMode) {
                editingMode = firstUnconfiguredMode ?? .openAICompatibleBYOK
                loadProviderFields()
            }
        }
    }

    private var firstUnconfiguredMode: ProviderMode? {
        DraftProviderFactory.supportedModes.first { !isProviderConfigured($0) }
    }

    private func saveImageProcessingModeRawValue(_ rawValue: String) {
        guard !isApplyingSyncedSettings else { return }

        let normalizedRawValue = LisdoSyncedSettings.normalizedImageProcessingModeRawValue(rawValue)
        guard normalizedRawValue == rawValue else {
            imageProcessingModeRawValue = normalizedRawValue
            return
        }
        guard syncedSettings.first?.imageProcessingModeRawValue != normalizedRawValue else { return }

        do {
            let settings = try syncedSettingsStore.updateImageProcessingModeRawValue(normalizedRawValue)
            applySyncedSettings(settings, updateEditingMode: false)
            status = "Image input mode saved."
        } catch {
            status = "Could not save image input mode: \(error.localizedDescription)"
        }
    }

    private func saveVoiceProcessingModeRawValue(_ rawValue: String) {
        guard !isApplyingSyncedSettings else { return }

        let normalizedRawValue = LisdoSyncedSettings.normalizedVoiceProcessingModeRawValue(rawValue)
        guard normalizedRawValue == rawValue else {
            voiceProcessingModeRawValue = normalizedRawValue
            return
        }
        guard syncedSettings.first?.voiceProcessingModeRawValue != normalizedRawValue else { return }

        do {
            let settings = try syncedSettingsStore.updateVoiceProcessingModeRawValue(normalizedRawValue)
            applySyncedSettings(settings, updateEditingMode: false)
            status = "Voice transcript mode saved."
        } catch {
            status = "Could not save voice transcript mode: \(error.localizedDescription)"
        }
    }

    private func loadProviderFields() {
        let settings = factory.loadSettings(for: editingMode)
        endpoint = settings.endpointURL?.absoluteString ?? ""
        model = settings.model
        displayName = settings.displayName ?? metadata.displayName
        apiKey = ""

        if editingMode == .macOnlyCLI {
            status = ""
        } else if metadata.requiresAPIKey {
            status = ""
        } else {
            status = ""
        }
    }

    private func save() {
        do {
            var savedStatus: String

            if editingMode == .macOnlyCLI {
                try preferenceStore.saveMacOnlyCLISettings(
                    MacOnlyCLILocalSettings(
                        descriptor: cliDescriptor(kind: cliKind, timeoutSeconds: cliTimeoutSeconds),
                        executablePath: cliExecutablePath
                    )
                )
                cliStatus = "\(cliDisplayName(cliKind)) strategy saved locally. Timeout \(Int(cliTimeoutSeconds)) seconds."
                savedStatus = "Mac-only CLI settings saved locally on this Mac. Captures still become drafts for review."
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
                    savedStatus = "\(settings.displayName ?? metadata.displayName) saved. \(apiKeyStorageMessage(for: editingMode))"
                } else if metadata.requiresAPIKey && !hasSavedKey(for: editingMode) {
                    savedStatus = "\(settings.displayName ?? metadata.displayName) endpoint and model saved. Add an API key before this provider can create drafts."
                } else {
                    savedStatus = "\(settings.displayName ?? metadata.displayName) settings saved."
                }
            }

            let settings = try syncedSettingsStore.updateProviderMode(editingMode)
            applySyncedSettings(settings, updateEditingMode: true)
            status = savedStatus
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

    private func notifyHotKeySettingsChanged() {
        NotificationCenter.default.post(name: LisdoMacNotifications.hotKeysChanged, object: nil)
    }

    private func reconcileProviderAfterRemoval(removedMode: ProviderMode) {
        guard providerMode == removedMode else { return }

        let nextMode = configuredProviderModes.first ?? .openAICompatibleBYOK
        if let settings = try? syncedSettingsStore.updateProviderMode(nextMode) {
            applySyncedSettings(settings, updateEditingMode: true)
        } else {
            providerMode = nextMode
            providerSelection = configuredProviderModes.contains(nextMode) ? .provider(nextMode) : .addMore
            providerStatus = "Provider removed, but synced provider selection could not be updated."
        }
    }

    private func apiKeyStorageMessage(for mode: ProviderMode) -> String {
        switch mode {
        case .openAICompatibleBYOK, .minimax, .anthropic, .gemini, .openRouter:
            return "Hosted BYOK API key syncs through Keychain when available."
        case .localModel:
            return "Local-model API key stays in this Mac's Keychain."
        case .ollama, .lmStudio, .macOnlyCLI:
            return "No hosted BYOK API key was saved."
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

private enum LisdoMacSettingsTab: String, CaseIterable, Identifiable {
    case capture
    case provider
    case hotkeys
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture:
            return "Capture"
        case .provider:
            return "Provider"
        case .hotkeys:
            return "Hotkeys"
        case .about:
            return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .capture:
            return "tray.and.arrow.down"
        case .provider:
            return "cpu"
        case .hotkeys:
            return "keyboard"
        case .about:
            return "info.circle"
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
