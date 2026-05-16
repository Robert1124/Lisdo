import AppKit
import AuthenticationServices
import LisdoCore
import SwiftData
import SwiftUI

private enum LisdoProviderGatePrimaryAction {
    case viewPlan
    case purchase
}

private struct LisdoProviderGateAlert: Identifiable {
    let id: String
    let title: String
    let message: String
    let primaryTitle: String
    let primaryAction: LisdoProviderGatePrimaryAction
}

struct LisdoMacProviderSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sparkleUpdater: LisdoMacSparkleUpdater
    @EnvironmentObject private var iCloudSyncStatusMonitor: LisdoICloudSyncStatusMonitor
    @EnvironmentObject private var entitlementStore: LisdoEntitlementStore
    @Query(sort: \LisdoSyncedSettings.updatedAt, order: .reverse) private var syncedSettings: [LisdoSyncedSettings]

    private let credentialStore = KeychainCredentialStore()
    private let preferenceStore = LisdoLocalProviderPreferenceStore()
    private let factory = DraftProviderFactory()
    private let accountSessionService = LisdoAccountSessionService()
    private let personalCenterURL = URL(string: "https://lisdo.robertw.me/account.html")!

    @State private var endpoint = ""
    @State private var model = ""
    @State private var displayName = ""
    @State private var apiKey = ""
    @State private var bearerToken = ""
    @State private var status = ""
    @State private var providerStatus = ""
    @State private var providerMode: ProviderMode = .openAICompatibleBYOK
    @State private var providerSelection: ProviderPickerSelection = .addMore
    @State private var suppressedProviderSelection: ProviderPickerSelection?
    @State private var providerConfigurationVisibility: ProviderConfigurationVisibility = .viewing
    @State private var lisdoProviderGateAlert: LisdoProviderGateAlert?
    @State private var isShowingLisdoPurchaseConfirmation = false
    @State private var editingMode: ProviderMode = .openAICompatibleBYOK
    @State private var cliKind: CLIProviderKind = .codex
    @State private var cliExecutablePath = ""
    @State private var cliTimeoutSeconds = 120.0
    @State private var cliStatus = ""
    @State private var imageProcessingModeRawValue = LisdoSyncedSettings.defaultImageProcessingModeRawValue
    @State private var voiceProcessingModeRawValue = LisdoSyncedSettings.defaultVoiceProcessingModeRawValue
    @State private var isApplyingSyncedSettings = false
    @State private var selectedSettingsTab: LisdoMacSettingsTab = .capture
    @State private var backendRefreshStatus = ""
    @State private var accountStatus = ""
    @State private var isAuthenticatingLisdoAccount = false
    @State private var isRefreshingBackend = false
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
        .onAppear {
            load()
            Task { await refreshLisdoBackendIfConfigured(silent: true) }
        }
        .onChange(of: syncedSettingsSnapshot) { _, _ in
            loadSyncedSelections(updateEditingMode: false)
        }
        .alert(item: $lisdoProviderGateAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                primaryButton: .default(Text(alert.primaryTitle)) {
                    handleLisdoProviderGatePrimaryAction(alert.primaryAction)
                },
                secondaryButton: .cancel(Text("Cancel")) {
                    restoreProviderPickerSelection()
                }
            )
        }
        .alert("Finished purchasing?", isPresented: $isShowingLisdoPurchaseConfirmation) {
            Button("Check plan") {
                Task { await confirmLisdoPurchaseAndMaybeSelectProvider() }
            }
            Button("Cancel", role: .cancel) {
                restoreProviderPickerSelection()
            }
        } message: {
            Text("After checkout or plan changes finish in the browser, Lisdo will ask the server for the latest plan and quota.")
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
        case .plan:
            planSettingsTab
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
        .lisdoSettingsFormSurface()
    }

    private var providerSettingsTab: some View {
        Form {
            Section {
                Picker("Provider", selection: $providerSelection) {
                    Text("Lisdo").tag(ProviderPickerSelection.provider(.lisdoManaged))
                    ForEach(configuredProviderModes, id: \.self) { mode in
                        Text(providerDisplayName(for: mode)).tag(ProviderPickerSelection.provider(mode))
                    }
                    Text("Add More Provider").tag(ProviderPickerSelection.addMore)
                }
                .pickerStyle(.menu)
                .onChange(of: providerSelection) { _, newSelection in
                    if suppressedProviderSelection == newSelection {
                        suppressedProviderSelection = nil
                        return
                    }
                    guard !isApplyingSyncedSettings else { return }
                    selectProvider(newSelection)
                }

                if !providerStatus.isEmpty {
                    Text(providerStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if providerConfigurationVisibility == .viewing, !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                selectedProviderActions
            } header: {
                Text("Provider")
            }

            if providerConfigurationVisibility.isExpanded {
                providerConfigurationSection
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
        .lisdoSettingsFormSurface()
    }

    @ViewBuilder
    private var selectedProviderActions: some View {
        switch providerSelection {
        case .provider(let mode):
            VStack(alignment: .leading, spacing: 10) {
                if mode != .lisdoManaged {
                    Text(providerSelectionDescription(for: mode))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if mode == .lisdoManaged {
                    lisdoQuotaPreview
                }

                if providerConfigurationVisibility == .viewing, mode != .lisdoManaged {
                    HStack {
                        Button {
                            beginEditingProvider(mode)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            removeSelectedProvider(mode)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        case .addMore:
            VStack(alignment: .leading, spacing: 10) {
                Text("Add a BYOK or Mac-local provider before organizing new drafts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if providerConfigurationVisibility == .viewing {
                    Button {
                        beginAddingProvider()
                    } label: {
                        Label("Configure provider", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var providerConfigurationSection: some View {
        Section {
            if providerConfigurationVisibility == .adding {
                Picker("Format", selection: $editingMode) {
                    ForEach(DraftProviderFactory.supportedModes.filter { $0 != .lisdoManaged }, id: \.self) { mode in
                        Text(DraftProviderFactory.metadata(for: mode).displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: editingMode) { _, _ in
                    loadProviderFields()
                }
            } else {
                LabeledContent("Format") {
                    Text(DraftProviderFactory.metadata(for: editingMode).displayName)
                }
            }

            Text(providerFormatHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            providerConfigurationFields

            if !status.isEmpty {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    saveAndCollapseProviderConfiguration()
                } label: {
                    Label("Save", systemImage: "key")
                }
                .buttonStyle(.borderedProminent)

                if editingMode != .lisdoManaged {
                    Button(role: .destructive) {
                        removeEditingProvider()
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isProviderConfigured(editingMode))
                }

                Button {
                    cancelProviderConfiguration()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
            }
        } header: {
            Text("Provider configuration")
        }
    }

    @ViewBuilder
    private var providerConfigurationFields: some View {
        if editingMode == .macOnlyCLI {
            cliFields
        } else if editingMode == .lisdoManaged {
            LabeledContent("Provider") {
                Text("Lisdo")
            }
            TextField("Endpoint", text: $endpoint)
                .textFieldStyle(.roundedBorder)
            TextField("Model", text: $model)
                .textFieldStyle(.roundedBorder)
            SecureField("Dev bearer token", text: $bearerToken)
                .textFieldStyle(.roundedBorder)
            Text("The Lisdo backend token is stored locally in UserDefaults for development.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
    }

    private var lisdoQuotaPreview: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Quota remaining")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(quotaRemainingLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: quotaRemainingFraction)
                .tint(LisdoMacTheme.ink1)
                .accessibilityLabel("Quota remaining")

            if !backendRefreshStatus.isEmpty {
                Text(backendRefreshStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var planSettingsTab: some View {
        Form {
            Section {
                if hasLisdoAccountSession {
                    signedInLisdoAccountCard
                } else {
                    signedOutLisdoAccountCard
                }
            } header: {
                Text("Lisdo account")
            }

            Section {
                Picker("Plan", selection: Binding(
                    get: { entitlementStore.selectedTier },
                    set: { selectPlan($0) }
                )) {
                    ForEach(LisdoPlanTier.allCases, id: \.self) { tier in
                        Text(tier.lisdoDisplayName).tag(tier)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("Sync") {
                    Text(iCloudSyncStatusMonitor.snapshot.title)
                }

                LabeledContent("Lisdo") {
                    Text(entitlementStore.snapshot.isFeatureEnabled(.lisdoManagedDrafts) ? "Enabled" : "Upgrade required")
                }

            } header: {
                Text("Plan")
            }
        }
        .lisdoSettingsFormSurface()
    }

    @ViewBuilder
    private var signedOutLisdoAccountCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 10) {
                Text("Sign in to sync Lisdo plan")
                    .font(.callout.weight(.semibold))
                Text("Mac can use the Lisdo plan and quota returned by the backend after sign in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email]
                } onCompletion: { result in
                    beginAppleSignInAuthentication(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(width: 260, height: 50)
                .disabled(isAuthenticatingLisdoAccount)

                if !accountStatus.isEmpty {
                    Text(accountStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var signedInLisdoAccountCard: some View {
        let summary = accountSessionService.currentAccountSummary()
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                Image(systemName: "person.crop.circle.fill.badge.checkmark")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(LisdoMacTheme.ink1)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(summary?.displayLabel ?? "Lisdo account")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(LisdoMacTheme.ink1)
                Text("Signed in on this Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !accountStatus.isEmpty {
                    Text(accountStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        }
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
        .lisdoSettingsFormSurface()
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
        .lisdoSettingsFormSurface()
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
        DraftProviderFactory.supportedModes.filter { mode in
            mode != .lisdoManaged && isProviderConfigured(mode)
        }
    }

    private var apiKeyPlaceholder: String {
        metadata.requiresAPIKey ? "API key" : "Optional API key"
    }

    private var hasLisdoAccountSession: Bool {
        accountSessionService.currentLisdoBearerToken() != nil
    }

    private var lisdoProviderGateDecision: LisdoManagedProviderGateDecision {
        LisdoManagedProviderGate.decision(
            snapshot: entitlementStore.effectiveSnapshot,
            hasLisdoAccountSession: hasLisdoAccountSession
        )
    }

    private var canUseLisdoProvider: Bool {
        lisdoProviderGateDecision == .allowed
    }

    private var quotaRemainingLabel: String {
        switch lisdoProviderGateDecision {
        case .requiresSignIn:
            return "Sign in required"
        case .planRequired:
            return "Plan required"
        case .quotaExhausted:
            return "Quota empty"
        case .allowed where entitlementStore.serverQuota != nil:
            return "Included usage"
        case .allowed:
            return "Local preview"
        }
    }

    private var mockQuotaRemainingFraction: Double {
        let balance = entitlementStore.snapshot.quotaBalance
        let monthlyUnits = balance.monthlyNonRolloverUnits
        guard monthlyUnits > 0 else { return 0.06 }
        let seed = (monthlyUnits % 19) + (balance.topUpRolloverUnits % 7) + 2
        return min(0.86, max(0.1, Double(seed) / 25.0))
    }

    private var quotaRemainingFraction: Double {
        entitlementStore.serverQuota?.remainingFraction ?? mockQuotaRemainingFraction
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
        case .lisdoManaged:
            return "Lisdo posts OpenAI-compatible chat requests to the staging backend and expects strict draft JSON in the response."
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
        if mode == .lisdoManaged {
            return canUseLisdoProvider
        }

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
        if settings.selectedProviderMode == .lisdoManaged && !canUseLisdoProvider {
            fallbackFromUnavailableLisdo(statusMessage: lisdoProviderUnavailableStatus(for: lisdoProviderGateDecision))
            return
        }

        let previousSelectedMode = providerMode
        let previousEditingMode = editingMode

        isApplyingSyncedSettings = true
        defer { isApplyingSyncedSettings = false }

        providerMode = settings.selectedProviderMode
        imageProcessingModeRawValue = settings.imageProcessingModeRawValue
        voiceProcessingModeRawValue = settings.voiceProcessingModeRawValue

        if settings.selectedProviderMode == .lisdoManaged || isProviderConfigured(settings.selectedProviderMode) {
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
            if mode == .lisdoManaged, !canUseLisdoProvider {
                promptForLisdoProviderGate(lisdoProviderGateDecision)
                return
            }

            providerConfigurationVisibility = .viewing
            updateSelectedProviderMode(mode)
        case .addMore:
            beginAddingProvider()
        }
    }

    private var firstUnconfiguredMode: ProviderMode? {
        DraftProviderFactory.supportedModes.first { mode in
            mode != .lisdoManaged && !isProviderConfigured(mode)
        }
    }

    @discardableResult
    private func updateSelectedProviderMode(_ mode: ProviderMode, updateEditingMode: Bool = true) -> Bool {
        do {
            let settings = try syncedSettingsStore.updateProviderMode(mode)
            applySyncedSettings(settings, updateEditingMode: updateEditingMode)
            return true
        } catch {
            providerStatus = "Could not save provider: \(error.localizedDescription)"
            restoreProviderPickerSelection()
            return false
        }
    }

    private func beginEditingProvider(_ mode: ProviderMode) {
        editingMode = mode
        loadProviderFields()
        providerConfigurationVisibility = .editing
    }

    private func beginAddingProvider() {
        providerStatus = ""
        editingMode = firstUnconfiguredMode ?? .openAICompatibleBYOK
        loadProviderFields()
        providerConfigurationVisibility = .adding
    }

    private func cancelProviderConfiguration() {
        providerConfigurationVisibility = .viewing
        editingMode = providerMode
        loadProviderFields()
        restoreProviderPickerSelection()
    }

    private func restoreProviderPickerSelection() {
        let restoredSelection = displayedSelectionForCurrentProvider
        guard providerSelection != restoredSelection else { return }
        suppressedProviderSelection = restoredSelection
        providerSelection = restoredSelection
    }

    private var displayedSelectionForCurrentProvider: ProviderPickerSelection {
        if providerMode == .lisdoManaged {
            return canUseLisdoProvider ? .provider(.lisdoManaged) : .addMore
        }

        return configuredProviderModes.contains(providerMode) ? .provider(providerMode) : .addMore
    }

    private func promptForLisdoProviderGate(_ decision: LisdoManagedProviderGateDecision) {
        providerStatus = lisdoProviderUnavailableStatus(for: decision)
        providerConfigurationVisibility = .viewing
        restoreProviderPickerSelection()
        lisdoProviderGateAlert = lisdoProviderGateAlert(for: decision)
    }

    private func lisdoProviderGateAlert(for decision: LisdoManagedProviderGateDecision) -> LisdoProviderGateAlert {
        switch decision {
        case .requiresSignIn:
            return LisdoProviderGateAlert(
                id: "requires-sign-in",
                title: "Sign in required",
                message: "Lisdo provider requires a signed-in Lisdo account and an active plan.",
                primaryTitle: "View Plan",
                primaryAction: .viewPlan
            )
        case .planRequired:
            return LisdoProviderGateAlert(
                id: "plan-required",
                title: "Plan required",
                message: "Your current plan does not include Lisdo provider. Purchase a Starter Trial or monthly plan to use Lisdo managed drafts.",
                primaryTitle: "Go purchase",
                primaryAction: .purchase
            )
        case .quotaExhausted:
            return LisdoProviderGateAlert(
                id: "quota-exhausted",
                title: "Lisdo usage is full",
                message: "This account has no Lisdo usage left. Upgrade your plan or buy a top-up to continue with Lisdo provider.",
                primaryTitle: "Upgrade or top up",
                primaryAction: .purchase
            )
        case .allowed:
            return LisdoProviderGateAlert(
                id: "allowed",
                title: "Lisdo available",
                message: "Lisdo provider is available for this account.",
                primaryTitle: "OK",
                primaryAction: .viewPlan
            )
        }
    }

    private func lisdoProviderUnavailableStatus(for decision: LisdoManagedProviderGateDecision) -> String {
        switch decision {
        case .requiresSignIn:
            return "Sign in to Lisdo and choose a plan before using Lisdo provider."
        case .planRequired:
            return "This account plan does not include Lisdo provider."
        case .quotaExhausted:
            return "Lisdo usage is full. Upgrade or buy a top-up to continue."
        case .allowed:
            return ""
        }
    }

    private func handleLisdoProviderGatePrimaryAction(_ action: LisdoProviderGatePrimaryAction) {
        switch action {
        case .viewPlan:
            selectedSettingsTab = .plan
        case .purchase:
            openPersonalCenter()
            isShowingLisdoPurchaseConfirmation = true
        }
    }

    @MainActor
    private func confirmLisdoPurchaseAndMaybeSelectProvider() async {
        accountStatus = "Checking Lisdo plan..."
        _ = await refreshLisdoBackendIfConfigured(silent: false)

        if canUseLisdoProvider {
            providerConfigurationVisibility = .viewing
            if updateSelectedProviderMode(.lisdoManaged) {
                providerStatus = "Lisdo selected for this plan."
                accountStatus = "Plan and quota are active on this Mac."
            }
        } else {
            let decision = lisdoProviderGateDecision
            restoreProviderPickerSelection()
            providerStatus = lisdoProviderUnavailableStatus(for: decision)
            accountStatus = providerStatus
        }
    }

    private func openPersonalCenter() {
        NSWorkspace.shared.open(personalCenterURL)
        accountStatus = "Opened Lisdo Personal Center in your browser."
        providerStatus = "Opened Personal Center for Lisdo plan management."
    }

    private func fallbackFromUnavailableLisdo(statusMessage: String) {
        let fallbackMode = configuredProviderModes.first ?? .openAICompatibleBYOK

        if updateSelectedProviderMode(fallbackMode) {
            if isProviderConfigured(fallbackMode) {
                providerConfigurationVisibility = .viewing
            } else {
                providerSelection = .addMore
                editingMode = firstUnconfiguredMode ?? .openAICompatibleBYOK
                loadProviderFields()
                providerConfigurationVisibility = .adding
            }
            providerStatus = statusMessage
        } else {
            providerMode = fallbackMode
            providerSelection = configuredProviderModes.contains(fallbackMode) ? .provider(fallbackMode) : .addMore
            providerStatus = "Lisdo is not available on Free, and the fallback provider could not be saved."
        }
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
        displayName = editingMode == .lisdoManaged ? "Lisdo" : settings.displayName ?? metadata.displayName
        apiKey = ""
        bearerToken = settings.bearerToken ?? (editingMode == .lisdoManaged ? "dev-token" : "")

        if editingMode == .macOnlyCLI {
            status = ""
        } else if metadata.requiresAPIKey {
            status = ""
        } else {
            status = ""
        }
    }

    @MainActor
    @discardableResult
    private func refreshLisdoBackendIfConfigured(silent: Bool) async -> Bool {
        guard !isRefreshingBackend else { return false }

        let settings = factory.loadSettings(for: .lisdoManaged)
        guard let endpointURL = settings.endpointURL else {
            if !silent {
                backendRefreshStatus = "Add a Lisdo endpoint before refreshing."
            }
            return false
        }

        let token = (settings.bearerToken ?? "dev-token").lisdoTrimmed
        guard !token.isEmpty else {
            if !silent {
                backendRefreshStatus = "Add a Lisdo bearer token before refreshing."
            }
            return false
        }

        isRefreshingBackend = true
        defer { isRefreshingBackend = false }

        do {
            _ = try await entitlementStore.refreshFromBackend(baseURL: endpointURL, bearerToken: token)
            backendRefreshStatus = ""
            return true
        } catch {
            if !silent {
                backendRefreshStatus = "Lisdo refresh failed: \(error.localizedDescription)"
            }
            return false
        }
    }

    private func beginAppleSignInAuthentication(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8)
            else {
                accountStatus = "Apple sign in did not return an identity token."
                return
            }
            let authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            Task { await authenticateLisdoAccount(identityToken: identityToken, authorizationCode: authorizationCode) }
        case .failure(let error):
            accountStatus = "Apple sign in failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func authenticateLisdoAccount(identityToken: String, authorizationCode: String?) async {
        guard !isAuthenticatingLisdoAccount else { return }
        isAuthenticatingLisdoAccount = true
        accountStatus = "Signing in to Lisdo..."
        defer { isAuthenticatingLisdoAccount = false }

        do {
            _ = try await accountSessionService.authenticateWithApple(
                identityToken: identityToken,
                authorizationCode: authorizationCode
            )
            loadProviderFields()
            await refreshLisdoBackendIfConfigured(silent: true)
            accountStatus = "Signed in. Plan and quota can now refresh on this Mac."
        } catch {
            accountStatus = "Apple sign in failed: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func save() -> Bool {
        guard editingMode != .lisdoManaged || canUseLisdoProvider else {
            status = lisdoProviderUnavailableStatus(for: lisdoProviderGateDecision)
            promptForLisdoProviderGate(lisdoProviderGateDecision)
            return false
        }

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
                    return false
                }

                if metadata.requiresAPIKey && apiKey.lisdoTrimmed.isEmpty && !hasSavedKey(for: editingMode) {
                    status = "Add an API key before saving this provider."
                    return false
                }

                let settings = DraftProviderLocalSettings(
                    mode: editingMode,
                    endpointURL: endpointURL,
                    model: model.lisdoTrimmed.isEmpty ? metadata.defaultModel : model.lisdoTrimmed,
                    displayName: editingMode == .lisdoManaged
                        ? "Lisdo"
                        : (displayName.lisdoTrimmed.isEmpty ? metadata.displayName : displayName.lisdoTrimmed),
                    requiresAPIKey: metadata.requiresAPIKey,
                    bearerToken: editingMode == .lisdoManaged ? managedBearerTokenForSaving : nil
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
            return true
        } catch {
            status = "Could not save provider settings: \(error.localizedDescription)"
            return false
        }
    }

    private func saveAndCollapseProviderConfiguration() {
        if save() {
            providerConfigurationVisibility = .viewing
            restoreProviderPickerSelection()
        }
    }

    private func removeSelectedProvider(_ mode: ProviderMode) {
        removeProvider(mode)
        providerConfigurationVisibility = .viewing
        restoreProviderPickerSelection()
    }

    private func removeEditingProvider() {
        removeProvider(editingMode)
        providerConfigurationVisibility = .viewing
        restoreProviderPickerSelection()
    }

    private func removeProvider(_ mode: ProviderMode) {
        guard mode != .lisdoManaged else {
            status = "Lisdo cannot be removed."
            return
        }

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

    private func selectPlan(_ tier: LisdoPlanTier) {
        let nextSnapshot = entitlementStore.updateSelectedTier(tier)
        let nextDecision = LisdoManagedProviderGate.decision(
            snapshot: nextSnapshot,
            hasLisdoAccountSession: hasLisdoAccountSession
        )

        if nextDecision == .allowed {
            providerConfigurationVisibility = .viewing
            if updateSelectedProviderMode(.lisdoManaged) {
                providerStatus = "Lisdo selected for this plan."
            }
        } else if providerMode == .lisdoManaged {
            fallbackFromUnavailableLisdo(statusMessage: lisdoProviderUnavailableStatus(for: nextDecision))
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
            return "Hosted BYOK API key is saved only in this device's Keychain."
        case .lisdoManaged:
            return "Lisdo backend token is saved only in local settings."
        case .localModel:
            return "Local-model API key stays in this Mac's Keychain."
        case .ollama, .lmStudio, .macOnlyCLI:
            return "No hosted BYOK API key was saved."
        }
    }

    private func providerDisplayName(for mode: ProviderMode) -> String {
        if mode == .lisdoManaged {
            return "Lisdo"
        }

        let savedName = factory.loadSettings(for: mode).displayName?.lisdoTrimmed
        if let savedName, !savedName.isEmpty {
            return savedName
        }
        return DraftProviderFactory.metadata(for: mode).displayName
    }

    private func providerSelectionDescription(for mode: ProviderMode) -> String {
        if mode == .lisdoManaged {
            return lisdoProviderUnavailableStatus(for: lisdoProviderGateDecision)
        }

        let modeMetadata = DraftProviderFactory.metadata(for: mode)
        if modeMetadata.isNormallyMacLocal {
            return "Configured locally for Mac processing."
        }

        if modeMetadata.requiresAPIKey {
            return hasSavedKey(for: mode)
                ? "API key is saved only in this Mac's Keychain."
                : "Add a local API key before organizing drafts with this provider."
        }

        return "Configured locally on this Mac."
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

    private var managedBearerTokenForSaving: String {
        bearerToken.lisdoTrimmed.isEmpty ? "dev-token" : bearerToken.lisdoTrimmed
    }
}

private enum LisdoMacSettingsTab: String, CaseIterable, Identifiable {
    case capture
    case provider
    case plan
    case hotkeys
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture:
            return "Capture"
        case .provider:
            return "Provider"
        case .plan:
            return "Plan"
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
        case .plan:
            return "person.badge.key"
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

private enum ProviderConfigurationVisibility: Equatable {
    case viewing
    case editing
    case adding

    var isExpanded: Bool {
        self != .viewing
    }
}

private extension View {
    func lisdoSettingsFormSurface() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(LisdoMacTheme.surface)
    }
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
