import LisdoCore
import SwiftData
import SwiftUI

struct YouSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var iCloudSyncStatusMonitor: LisdoICloudSyncStatusMonitor

    private let credentialStore = KeychainCredentialStore()
    private let providerFactory = DraftProviderFactory()

    @State private var endpoint = ""
    @State private var model = ""
    @State private var displayName = ""
    @State private var apiKey = ""
    @State private var keyStatus = "Not saved"
    @State private var providerMode = ProviderMode.openAICompatibleBYOK
    @State private var providerModeStatus = "Syncs between iPhone and Mac."
    @State private var notificationStatus = LisdoNotificationStatus(
        title: "Checking notifications",
        detail: "Notification permission is optional and never blocks capture.",
        actionTitle: nil,
        canRequestPermission: false,
        allowsDelivery: false
    )
    @State private var isRequestingNotifications = false
    @State private var imageProcessingModeRawValue = LisdoSyncedSettings.defaultImageProcessingModeRawValue
    @State private var voiceProcessingModeRawValue = LisdoSyncedSettings.defaultVoiceProcessingModeRawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                iCloudSection
                processingModeSection
                captureInputSection
                notificationSection
                providerSection
                localSecretsNotice
            }
            .padding(16)
        }
        .background(LisdoTheme.surface)
        .navigationTitle("You")
        .onAppear {
            loadProviderSettings()
            iCloudSyncStatusMonitor.refresh()
            Task { await refreshNotificationStatus() }
        }
        .onChange(of: providerMode) { _, newValue in
            loadProviderFields(for: newValue)
            saveProviderMode(newValue)
        }
        .onChange(of: imageProcessingModeRawValue) { _, newValue in
            saveImageProcessingMode(newValue)
        }
        .onChange(of: voiceProcessingModeRawValue) { _, newValue in
            saveVoiceProcessingMode(newValue)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Local provider setup and product settings.")
                .font(.system(size: 13))
                .foregroundStyle(LisdoTheme.ink3)
        }
        .padding(.horizontal, 4)
    }

    private var iCloudSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LisdoSectionHeader(title: "iCloud", detail: iCloudSyncStatusMonitor.snapshot.isCloudBacked ? "Sync" : "Local")

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iCloudSyncStatusMonitor.snapshot.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(iCloudSyncStatusMonitor.snapshot.isCloudBacked ? LisdoTheme.ok : LisdoTheme.ink3)
                    .frame(width: 30, height: 30)
                    .background(LisdoTheme.surface3, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(iCloudSyncStatusMonitor.snapshot.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(LisdoTheme.ink1)
                    Text(iCloudSyncStatusMonitor.snapshot.detail ?? "Lisdo stores categories, captures, drafts, todos, blocks, and reminders in its SwiftData store.")
                        .font(.system(size: 12))
                        .lineSpacing(2)
                        .foregroundStyle(LisdoTheme.ink3)
                }
            }

            Button {
                iCloudSyncStatusMonitor.refresh()
            } label: {
                Label("Refresh status", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(LisdoTonalButtonStyle())
        }
        .lisdoCard()
    }

    private var processingModeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LisdoSectionHeader(title: "Capture processing", detail: "Daily capture")

            ProductStateRow(
                icon: "icloud",
                title: "Product settings sync",
                message: "Selected provider mode and image input mode sync between iPhone and Mac. Voice captures always use transcript-first processing."
            )

            Picker("Processing mode", selection: $providerMode) {
                ForEach(DraftProviderFactory.supportedModes, id: \.self) { mode in
                    Text(DraftProviderFactory.metadata(for: mode).displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: selectedMetadata.isNormallyMacLocal ? "desktopcomputer" : "key")
                        .foregroundStyle(LisdoTheme.ink3)
                    Text(providerModeTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(LisdoTheme.ink1)
                }

                Text(providerModeDescription)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundStyle(LisdoTheme.ink3)

                Text(providerModeStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(LisdoTheme.ink4)
            }
            .padding(12)
            .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .lisdoCard()
    }

    private var captureInputSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LisdoSectionHeader(title: "Capture input", detail: "Image and voice")

            Text("These product settings sync between iPhone and Mac. API keys use Keychain; Mac CLI paths and local provider details stay Mac-local.")
                .font(.system(size: 12))
                .lineSpacing(2)
                .foregroundStyle(LisdoTheme.ink3)

            LisdoSegmentedControl(
                selection: $imageProcessingModeRawValue,
                options: LisdoImageProcessingMode.allCases.map { mode in
                    (value: mode.rawValue, title: imageInputTitle(for: mode))
                }
            )

            Text(selectedImageProcessingMode.detailText)
                .font(.system(size: 12))
                .lineSpacing(2)
                .foregroundStyle(LisdoTheme.ink3)

            ProductStateRow(
                icon: "text.bubble",
                title: "Voice uses transcript first",
                message: selectedVoiceProcessingMode.detailText
            )
        }
        .lisdoCard()
    }

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LisdoSectionHeader(title: "Notifications", detail: "Optional")

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: notificationStatus.allowsDelivery ? "bell.badge" : "bell.slash")
                    .font(.system(size: 15))
                    .foregroundStyle(notificationStatus.allowsDelivery ? LisdoTheme.ok : LisdoTheme.ink3)
                    .frame(width: 28, height: 28)
                    .background(LisdoTheme.surface3, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(notificationStatus.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(LisdoTheme.ink1)
                    Text(notificationStatus.detail)
                        .font(.system(size: 12))
                        .lineSpacing(2)
                        .foregroundStyle(LisdoTheme.ink3)
                }
            }

            HStack(spacing: 10) {
                if notificationStatus.canRequestPermission, let actionTitle = notificationStatus.actionTitle {
                    Button {
                        Task { await requestNotificationPermission() }
                    } label: {
                        Label(actionTitle, systemImage: "bell")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LisdoTonalButtonStyle())
                    .disabled(isRequestingNotifications)
                }

                Button {
                    Task { await refreshNotificationStatus() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(maxWidth: notificationStatus.canRequestPermission ? nil : .infinity)
                }
                .buttonStyle(LisdoTonalButtonStyle())
                .disabled(isRequestingNotifications)
            }
        }
        .lisdoCard()
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LisdoSectionHeader(title: selectedMetadata.displayName, detail: selectedMetadata.requiresAPIKey ? "API provider" : "Local provider")

            if selectedMetadata.mode == .macOnlyCLI {
                ProductStateRow(
                    icon: "desktopcomputer",
                    title: "Configured on Mac",
                    message: "Mac-only CLI captures can be selected on iPhone, but command paths and CLI credentials stay on the Mac that processes the queue."
                )
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Endpoint")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LisdoTheme.ink3)
                    TextField(selectedMetadata.defaultEndpointURL?.absoluteString ?? "Provider endpoint", text: $endpoint)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .textFieldStyle(LisdoProviderFieldStyle())
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Model")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LisdoTheme.ink3)
                TextField("Model name", text: $model)
                    .textInputAutocapitalization(.never)
                    .textFieldStyle(LisdoProviderFieldStyle())
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Display name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LisdoTheme.ink3)
                TextField(selectedMetadata.displayName, text: $displayName)
                    .textFieldStyle(LisdoProviderFieldStyle())
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("API key")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LisdoTheme.ink3)
                SecureField("Stored locally in Keychain", text: $apiKey)
                    .textContentType(.password)
                    .textFieldStyle(LisdoProviderFieldStyle())
                    .disabled(!selectedMetadata.requiresAPIKey)
                Text(keyStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(LisdoTheme.ink3)
            }

            Button {
                saveProviderSettings()
            } label: {
                Label("Save provider settings", systemImage: "key")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(LisdoTonalButtonStyle(height: 48))
        }
        .lisdoCard()
    }

    private var localSecretsNotice: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Secrets stay local", systemImage: "lock")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(LisdoTheme.ink1)
            Text("Hosted BYOK API keys are saved in synchronizable Keychain with a local fallback. CLI paths, OAuth tokens, local model endpoints, and Mac provider secrets remain Mac-local and are not synced through iCloud.")
                .font(.system(size: 12))
                .lineSpacing(2)
                .foregroundStyle(LisdoTheme.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lisdoCard()
    }

    private func loadProviderSettings() {
        do {
            let settings = try syncedSettingsStore.fetchOrCreateSettings()
            providerMode = settings.selectedProviderMode
            imageProcessingModeRawValue = LisdoSyncedSettings.normalizedImageProcessingModeRawValue(settings.imageProcessingModeRawValue)
            voiceProcessingModeRawValue = LisdoSyncedSettings.normalizedVoiceProcessingModeRawValue(settings.voiceProcessingModeRawValue)
            providerModeStatus = "Selected provider and input modes sync between iPhone and Mac."
            loadProviderFields(for: providerMode)
        } catch {
            providerModeStatus = "Could not load synced settings: \(error.localizedDescription)"
            loadProviderFields(for: providerMode)
        }
    }

    private func loadProviderFields(for mode: ProviderMode) {
        let settings = providerFactory.loadSettings(for: mode)
        endpoint = settings.endpointURL?.absoluteString ?? ""
        model = settings.model
        displayName = settings.displayName ?? DraftProviderFactory.metadata(for: mode).displayName
        apiKey = ""

        if DraftProviderFactory.metadata(for: mode).requiresAPIKey {
            let existingKey = (try? credentialStore.readAPIKey(for: mode)) ?? (mode == .openAICompatibleBYOK ? (try? credentialStore.readOpenAICompatibleAPIKey()) : nil)
            keyStatus = (existingKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? "API key is saved in synchronizable Keychain with local fallback."
                : "No API key saved for this provider."
        } else {
            keyStatus = "No API key required. CLI paths and local endpoints stay on the Mac that uses them."
        }
    }

    private func saveProviderMode(_ mode: ProviderMode) {
        do {
            try syncedSettingsStore.updateProviderMode(mode)
            providerModeStatus = "Selected provider mode syncs between iPhone and Mac."
        } catch {
            providerModeStatus = "Could not save synced provider mode: \(error.localizedDescription)"
        }
    }

    private func saveImageProcessingMode(_ rawValue: String) {
        do {
            let settings = try syncedSettingsStore.updateImageProcessingModeRawValue(rawValue)
            imageProcessingModeRawValue = settings.imageProcessingModeRawValue
        } catch {
            providerModeStatus = "Could not save synced image input mode: \(error.localizedDescription)"
        }
    }

    private func saveVoiceProcessingMode(_ rawValue: String) {
        do {
            let settings = try syncedSettingsStore.updateVoiceProcessingModeRawValue(rawValue)
            voiceProcessingModeRawValue = settings.voiceProcessingModeRawValue
        } catch {
            providerModeStatus = "Could not save synced voice transcript mode: \(error.localizedDescription)"
        }
    }

    private func saveProviderSettings() {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointURL = trimmedEndpoint.isEmpty ? nil : URL(string: trimmedEndpoint)
        if selectedMetadata.mode != .macOnlyCLI, endpointURL == nil {
            keyStatus = "Enter a valid endpoint URL."
            return
        }

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let settings = DraftProviderLocalSettings(
                mode: providerMode,
                endpointURL: endpointURL,
                model: trimmedModel.isEmpty ? selectedMetadata.defaultModel : trimmedModel,
                displayName: trimmedDisplayName.isEmpty ? selectedMetadata.displayName : trimmedDisplayName,
                requiresAPIKey: selectedMetadata.requiresAPIKey
            )
            try credentialStore.saveProviderSettings(settings)

            if providerMode == .openAICompatibleBYOK, let endpointURL {
                try credentialStore.saveOpenAICompatibleSettings(endpointURL: endpointURL, model: settings.model)
            }

            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedKey.isEmpty {
                try credentialStore.saveAPIKey(trimmedKey, for: providerMode)
                if providerMode == .openAICompatibleBYOK {
                    try credentialStore.saveOpenAICompatibleAPIKey(trimmedKey)
                }
                apiKey = ""
                keyStatus = selectedMetadata.requiresAPIKey
                    ? "Provider settings saved. Hosted API key is in synchronizable Keychain."
                    : "Provider settings saved. No API key is required."
            } else {
                keyStatus = selectedMetadata.requiresAPIKey
                    ? "Provider settings saved. Existing Keychain key was left unchanged."
                    : "Provider settings saved locally. No secret is synced."
            }

            _ = try? syncedSettingsStore.updateProviderMode(providerMode)
        } catch {
            keyStatus = "Could not save provider settings: \(error)"
        }
    }

    @MainActor
    private func refreshNotificationStatus() async {
        notificationStatus = await LisdoNotificationFeedback.currentStatus()
    }

    @MainActor
    private func requestNotificationPermission() async {
        isRequestingNotifications = true
        defer { isRequestingNotifications = false }
        notificationStatus = await LisdoNotificationFeedback.requestPermission()
    }

    private var providerModeTitle: String {
        if selectedMetadata.isNormallyMacLocal {
            "Queue captures for Mac processing"
        } else {
            "Create drafts on this iPhone"
        }
    }

    private var providerModeDescription: String {
        if selectedMetadata.isNormallyMacLocal {
            return "Captures can be queued from iPhone and processed later on a Mac. Lisdo will not call localhost or CLI tools from iPhone."
        }
        return "Hosted API modes create ProcessingDraft items on this iPhone when local provider settings and required keys are available."
    }

    private var selectedMetadata: DraftProviderModeMetadata {
        DraftProviderFactory.metadata(for: providerMode)
    }

    private var selectedImageProcessingMode: LisdoImageProcessingMode {
        LisdoImageProcessingMode(rawValue: imageProcessingModeRawValue) ?? .visionOCR
    }

    private var selectedVoiceProcessingMode: LisdoVoiceProcessingMode {
        LisdoVoiceProcessingMode(rawValue: voiceProcessingModeRawValue) ?? .speechTranscript
    }

    private func imageInputTitle(for mode: LisdoImageProcessingMode) -> String {
        switch mode {
        case .visionOCR:
            return "OCR"
        case .directLLM:
            return "Image LLM"
        }
    }

    private var syncedSettingsStore: LisdoSyncedSettingsStore {
        LisdoSyncedSettingsStore(context: modelContext)
    }
}
