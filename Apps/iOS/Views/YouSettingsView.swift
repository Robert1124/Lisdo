import AuthenticationServices
import Foundation
import LisdoCore
import StoreKit
import SwiftData
import SwiftUI

struct YouSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var iCloudSyncStatusMonitor: LisdoICloudSyncStatusMonitor
    @EnvironmentObject private var entitlementStore: LisdoEntitlementStore

    private let credentialStore = KeychainCredentialStore()
    private let preferenceStore = LisdoLocalProviderPreferenceStore()
    private let providerFactory = DraftProviderFactory()
    private let accountSessionService = LisdoAccountSessionService()
    private let settingsSheetHorizontalPadding: CGFloat = 18
    private let settingsSheetTopPadding: CGFloat = 26
    private let settingsSheetBottomPadding: CGFloat = 22

    @StateObject private var storeKitService = LisdoStoreKitService()

    @State private var endpoint = ""
    @State private var model = ""
    @State private var displayName = ""
    @State private var apiKey = ""
    @State private var bearerToken = ""
    @State private var keyStatus = "No key saved"
    @State private var providerMode = ProviderMode.openAICompatibleBYOK
    @State private var editingProviderMode = ProviderMode.openAICompatibleBYOK
    @State private var providerModeStatus = ""
    @State private var backendRefreshStatus = ""
    @State private var purchaseStatus = ""
    @State private var accountSummary: LisdoAccountSessionSummary?
    @State private var isAuthenticatingLisdoAccount = false
    @State private var isPurchasingOrRestoring = false
    @State private var isRefreshingBackend = false
    @State private var pendingStoreProductAfterSignIn: LisdoStoreProductID?
    @State private var shouldRestorePurchasesAfterSignIn = false
    @State private var activeSettingsSheet: YouSettingsSheet?
    @State private var notificationStatus = LisdoNotificationStatus(
        title: "Checking notifications",
        detail: "",
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
                accountSection
                iCloudSection
                planSection
                providerSummarySection
                captureInputSection
                notificationSection
            }
            .padding(16)
        }
        .background(LisdoTheme.surface)
        .navigationTitle("You")
        .sheet(item: $activeSettingsSheet) { sheet in
            settingsSheet(for: sheet)
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            loadProviderSettings()
            loadAccountSessionState()
            iCloudSyncStatusMonitor.refresh()
            Task {
                await refreshLisdoAccountSummaryIfNeeded()
                await refreshLisdoBackendIfConfigured(silent: true)
            }
            Task { await refreshNotificationStatus() }
        }
        .onChange(of: imageProcessingModeRawValue) { _, newValue in
            saveImageProcessingMode(newValue)
        }
        .onChange(of: voiceProcessingModeRawValue) { _, newValue in
            saveVoiceProcessingMode(newValue)
        }
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
                    if let detail = iCloudIssueDetail {
                        Text(detail)
                            .font(.system(size: 12))
                            .lineSpacing(2)
                            .foregroundStyle(LisdoTheme.ink3)
                    }
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

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LisdoSectionHeader(title: "Plan", detail: planSourceLabel)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: planDisplaySnapshot.isFeatureEnabled(.lisdoManagedDrafts) ? "sparkles" : "key")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(LisdoTheme.ink2)
                        .frame(width: 30, height: 30)
                        .background(LisdoTheme.surface3, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(planDisplaySnapshot.tier.lisdoDisplayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(LisdoTheme.ink1)
                    }

                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Quota remaining")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(LisdoTheme.ink3)
                        Spacer()
                        Text(quotaRemainingLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(LisdoTheme.ink4)
                    }

                    ProgressView(value: quotaRemainingFraction)
                        .tint(LisdoTheme.ink1)
                        .accessibilityLabel("Quota remaining")
                }

                if !backendRefreshStatus.isEmpty {
                    Text(backendRefreshStatus)
                        .font(.system(size: 11))
                        .lineSpacing(2)
                        .foregroundStyle(LisdoTheme.ink4)
                }
            }

            HStack(spacing: 10) {
                Button {
                    activeSettingsSheet = .plan
                } label: {
                    Label(planActionTitle, systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(LisdoTonalButtonStyle())

                Button {
                    Task { await refreshLisdoBackendIfConfigured(silent: false) }
                } label: {
                    Label("Refresh Lisdo", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(LisdoTonalButtonStyle())
                .disabled(isRefreshingBackend)
            }
        }
        .lisdoCard()
    }

    private var accountSection: some View {
        Group {
            if isLisdoAccountSignedIn {
                signedInAccountProfileCard(allowsSignOut: true)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    LisdoSectionHeader(title: "Lisdo account", detail: "Required")
                    signedOutAccountCard(allowsSignIn: true)
                }
                .lisdoCard()
            }
        }
    }

    private var providerSummarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LisdoSectionHeader(title: "Provider", detail: "Drafts")

            Button {
                activeSettingsSheet = .providerSelection
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: selectedMetadata.mode == .lisdoManaged ? "sparkles" : selectedMetadata.isNormallyMacLocal ? "desktopcomputer" : "key")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(LisdoTheme.ink3)
                        .frame(width: 30, height: 30)
                        .background(LisdoTheme.surface3, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(providerDisplayName(for: providerMode))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(LisdoTheme.ink1)
                        Text(providerSummary)
                            .font(.system(size: 12))
                            .lineSpacing(2)
                            .foregroundStyle(LisdoTheme.ink3)

                        if !providerModeStatus.isEmpty {
                            Text(providerModeStatus)
                                .font(.system(size: 11))
                                .foregroundStyle(LisdoTheme.ink4)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LisdoTheme.ink4)
                }
                .padding(12)
                .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .lisdoCard()
    }

    private var captureInputSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LisdoSectionHeader(title: "Capture input", detail: "Image")

            ImageProcessingModeSelector(selection: $imageProcessingModeRawValue)
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
                    if let detail = notificationIssueDetail {
                        Text(detail)
                            .font(.system(size: 12))
                            .lineSpacing(2)
                            .foregroundStyle(LisdoTheme.ink3)
                    }
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

    @ViewBuilder
    private func settingsSheet(for sheet: YouSettingsSheet) -> some View {
        switch sheet {
        case .plan:
            planManagementSheet
                .presentationDetents([.medium, .large])
        case .accountSignIn:
            accountSignInSheet
                .presentationDetents([.medium])
        case .providerSelection:
            providerSelectionSheet
                .presentationDetents([.medium, .large])
        case .providerConfiguration:
            providerConfigurationSheet
                .presentationDetents([.large])
        }
    }

    private var planManagementSheet: some View {
        settingsSheetContainer {
            sheetHeader(
                title: entitlementStore.selectedTier == .free ? "Upgrade Plan" : "Manage Plan",
                detail: "Purchase or restore a plan. Lisdo refreshes quota after the App Store transaction is verified."
            )

            VStack(spacing: 10) {
                ForEach(LisdoPlanTier.allCases, id: \.self) { tier in
                    planRow(for: tier)
                }

                if planDisplaySnapshot.canUseTopUpQuota {
                    topUpRow
                }
            }

            if !purchaseStatus.isEmpty {
                Text(purchaseStatus)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundStyle(LisdoTheme.ink3)
            }
        } actions: {
            Button {
                Task { await restorePurchases() }
            } label: {
                Label("Restore purchases", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(LisdoTonalButtonStyle())
            .disabled(isAuthenticatingLisdoAccount || isPurchasingOrRestoring)
        }
        .task {
            _ = try? await storeKitService.loadProducts()
        }
    }

    private var accountSignInSheet: some View {
        settingsSheetContainer {
            sheetHeader(
                title: "Sign in to Continue",
                detail: "Use Sign in with Apple before starting App Store purchases so Lisdo can sync plan and quota across devices."
            )

            lisdoAccountStatusCard(allowsSignIn: true)

            if !purchaseStatus.isEmpty {
                Text(purchaseStatus)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundStyle(LisdoTheme.ink3)
            }
        } actions: {
            Button {
                pendingStoreProductAfterSignIn = nil
                shouldRestorePurchasesAfterSignIn = false
                activeSettingsSheet = .plan
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(LisdoTonalButtonStyle())
        }
    }

    private func planRow(for tier: LisdoPlanTier) -> some View {
        Button {
            Task { await selectOrPurchasePlan(tier) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: entitlementStore.selectedTier == tier ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(entitlementStore.selectedTier == tier ? LisdoTheme.ink1 : LisdoTheme.ink4)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 5) {
                    Text(tier.lisdoDisplayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LisdoTheme.ink1)
                    Text(planDescription(for: tier))
                        .font(.system(size: 12))
                        .lineSpacing(2)
                        .foregroundStyle(LisdoTheme.ink3)
                }

                Spacer(minLength: 0)

                Text(planPriceLabel(for: tier))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LisdoTheme.ink3)
            }
            .padding(13)
            .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(entitlementStore.selectedTier == tier ? LisdoTheme.ink1.opacity(0.28) : LisdoTheme.divider.opacity(0.75), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isAuthenticatingLisdoAccount || isPurchasingOrRestoring)
    }

    private var topUpRow: some View {
        Button {
            Task { await purchaseStoreProduct(.topUpUsage) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(LisdoTheme.ink4)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Usage Top-Up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LisdoTheme.ink1)
                    Text("Adds rollover usage after the monthly included quota is used.")
                        .font(.system(size: 12))
                        .lineSpacing(2)
                        .foregroundStyle(LisdoTheme.ink3)
                }

                Spacer(minLength: 0)

                Text(storeKitService.products[LisdoStoreProductID.topUpUsage.rawValue]?.displayPrice ?? "$9.99")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LisdoTheme.ink3)
            }
            .padding(13)
            .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(LisdoTheme.divider.opacity(0.75), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isAuthenticatingLisdoAccount || isPurchasingOrRestoring)
    }

    @ViewBuilder
    private func lisdoAccountStatusCard(allowsSignIn: Bool) -> some View {
        if isLisdoAccountSignedIn {
            signedInAccountProfileCard(allowsSignOut: allowsSignIn)
        } else {
            signedOutAccountCard(allowsSignIn: allowsSignIn)
        }
    }

    @ViewBuilder
    private func signedInAccountProfileCard(allowsSignOut: Bool) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                signedInAccountProfileContent(allowsSignOut: allowsSignOut)
                    .padding(18)
                    .frame(minHeight: 104)
                    .glassEffect(.regular.tint(.white.opacity(0.18)), in: .rect(cornerRadius: 28))
            }
        } else {
            signedInAccountProfileContent(allowsSignOut: allowsSignOut)
                .padding(18)
                .frame(minHeight: 104)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(LisdoTheme.divider.opacity(0.58), lineWidth: 1)
                }
        }
    }

    private func signedInAccountProfileContent(allowsSignOut: Bool) -> some View {
        HStack(spacing: 16) {
            accountAvatar

            VStack(alignment: .leading, spacing: 4) {
                Text(accountProfileName)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(LisdoTheme.ink1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                if let detail = accountProfileDetail {
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundStyle(LisdoTheme.ink3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }

            Spacer(minLength: 0)

            if allowsSignOut {
                accountSignOutButton
            }
        }
    }

    @ViewBuilder
    private var accountAvatar: some View {
        let initial = accountAvatarInitial
        if #available(iOS 26.0, *) {
            ZStack {
                Circle()
                    .fill(LisdoTheme.surface.opacity(0.1))
                if let initial {
                    Text(initial)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(LisdoTheme.ink1)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(LisdoTheme.ink2)
                }
            }
            .frame(width: 64, height: 64)
            .glassEffect(.regular, in: Circle())
        } else {
            ZStack {
                Circle()
                    .fill(LisdoTheme.surface3)
                if let initial {
                    Text(initial)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(LisdoTheme.ink1)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(LisdoTheme.ink2)
                }
            }
            .frame(width: 64, height: 64)
        }
    }

    @ViewBuilder
    private var accountSignOutButton: some View {
        if #available(iOS 26.0, *) {
            Button {
                signOutLisdoAccount()
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(LisdoTheme.ink2)
                    .frame(width: 54, height: 54)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .accessibilityLabel("Sign out")
            .disabled(isAuthenticatingLisdoAccount || isPurchasingOrRestoring)
        } else {
            Button {
                signOutLisdoAccount()
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(LisdoTheme.ink2)
                    .frame(width: 54, height: 54)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(LisdoTheme.divider.opacity(0.65), lineWidth: 1)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sign out")
            .disabled(isAuthenticatingLisdoAccount || isPurchasingOrRestoring)
        }
    }

    private func signedOutAccountCard(allowsSignIn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LisdoTheme.ink3)
                    .frame(width: 30, height: 30)
                    .background(LisdoTheme.surface3, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Lisdo account required")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LisdoTheme.ink1)
                    Text(lisdoAccountDetailText)
                        .font(.system(size: 12))
                        .lineSpacing(2)
                        .foregroundStyle(LisdoTheme.ink3)
                }
            }

            if allowsSignIn {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    beginAppleSignInAuthentication(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(isAuthenticatingLisdoAccount || isPurchasingOrRestoring)
            }
        }
        .padding(13)
        .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var providerSelectionSheet: some View {
        settingsSheetContainer {
            sheetHeader(
                title: "Provider",
                detail: "Choose a configured draft provider. AI output still opens as a draft for review."
            )

            VStack(spacing: 10) {
                providerSelectionRow(for: .lisdoManaged, isLocked: !canUseLisdoManagedProvider)

                ForEach(configuredProviderModes, id: \.self) { mode in
                    providerSelectionRow(for: mode, isLocked: false)
                }
            }
        } actions: {
            Button {
                editingProviderMode = firstProviderModeForConfiguration
                loadProviderFields(for: editingProviderMode)
                activeSettingsSheet = .providerConfiguration
            } label: {
                Label("Add provider", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(LisdoTonalButtonStyle())
        }
    }

    private func providerSelectionRow(for mode: ProviderMode, isLocked: Bool) -> some View {
        Button {
            selectProvider(mode)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: providerMode == mode ? "checkmark.circle.fill" : isLocked ? "lock.circle" : "circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(providerMode == mode ? LisdoTheme.ink1 : LisdoTheme.ink4)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 5) {
                    Text(providerDisplayName(for: mode))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LisdoTheme.ink1)
                    Text(providerSelectionDescription(for: mode, isLocked: isLocked))
                        .font(.system(size: 12))
                        .lineSpacing(2)
                        .foregroundStyle(LisdoTheme.ink3)
                }

                Spacer(minLength: 0)
            }
            .padding(13)
            .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(providerMode == mode ? LisdoTheme.ink1.opacity(0.28) : LisdoTheme.divider.opacity(0.75), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var providerConfigurationSheet: some View {
        settingsSheetContainer {
            sheetHeader(
                title: "Provider Settings",
                detail: "Provider endpoints, tokens, and API keys stay on this device."
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Provider")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LisdoTheme.ink3)
                Picker("Provider", selection: $editingProviderMode) {
                    ForEach(DraftProviderFactory.supportedModes, id: \.self) { mode in
                        Text(DraftProviderFactory.metadata(for: mode).displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: editingProviderMode) { _, newValue in
                    loadProviderFields(for: newValue)
                }
            }

            providerConfigurationFields

            if !keyStatus.isEmpty {
                Text(keyStatus)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundStyle(LisdoTheme.ink3)
            }
        } actions: {
            Button {
                saveProviderSettings()
            } label: {
                Label("Save provider", systemImage: "key")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(LisdoTonalButtonStyle(isProminent: true, height: 48))
        }
    }

    private func settingsSheetContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        settingsSheetScrollContent(content: content)
            .background(LisdoTheme.surface)
    }

    private func settingsSheetContainer<Content: View, Actions: View>(
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        settingsSheetScrollContent(content: content)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(LisdoTheme.divider.opacity(0.7))
                        .frame(height: 1)

                    actions()
                        .padding(.horizontal, settingsSheetHorizontalPadding)
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                }
                .background(LisdoTheme.surface)
            }
            .background(LisdoTheme.surface)
    }

    private func settingsSheetScrollContent<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, settingsSheetHorizontalPadding)
            .padding(.top, settingsSheetTopPadding)
            .padding(.bottom, settingsSheetBottomPadding)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var providerConfigurationFields: some View {
        if editingProviderMode == .macOnlyCLI {
            Label("Mac-only CLI setup is saved from the Mac app. Once configured there, iPhone captures can queue for Mac processing.", systemImage: "desktopcomputer")
                .font(.system(size: 13))
                .lineSpacing(2)
                .foregroundStyle(LisdoTheme.ink3)
                .padding(13)
                .background(LisdoTheme.surface2, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        } else if editingProviderMode == .lisdoManaged {
            providerField(title: "Dev endpoint") {
                TextField(editingMetadata.defaultEndpointURL?.absoluteString ?? "Endpoint", text: $endpoint)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .textFieldStyle(LisdoProviderFieldStyle())
            }

            providerField(title: "Dev bearer token") {
                SecureField("dev-token", text: $bearerToken)
                    .textContentType(.password)
                    .textFieldStyle(LisdoProviderFieldStyle())
                Text("Saved in local settings for backend development.")
                    .font(.system(size: 11))
                    .foregroundStyle(LisdoTheme.ink3)
            }
        } else {
            providerField(title: "Display name") {
                TextField(editingMetadata.displayName, text: $displayName)
                    .textFieldStyle(LisdoProviderFieldStyle())
            }

            providerField(title: "Endpoint") {
                TextField(editingMetadata.defaultEndpointURL?.absoluteString ?? "Provider endpoint", text: $endpoint)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .textFieldStyle(LisdoProviderFieldStyle())
            }

            providerField(title: "Model") {
                TextField("Model name", text: $model)
                    .textInputAutocapitalization(.never)
                    .textFieldStyle(LisdoProviderFieldStyle())
            }

            providerField(title: editingMetadata.requiresAPIKey ? "API key" : "API key (optional)") {
                SecureField("API key", text: $apiKey)
                    .textContentType(.password)
                    .textFieldStyle(LisdoProviderFieldStyle())
                Text(apiKeyLocalStorageCopy(for: editingProviderMode))
                    .font(.system(size: 11))
                    .foregroundStyle(LisdoTheme.ink3)
            }
        }
    }

    private func providerField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LisdoTheme.ink3)
            content()
        }
    }

    private func sheetHeader(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(LisdoTheme.ink1)
            Text(detail)
                .font(.system(size: 13))
                .lineSpacing(2)
                .foregroundStyle(LisdoTheme.ink3)
        }
    }

    private func loadProviderSettings() {
        do {
            let settings = try syncedSettingsStore.fetchOrCreateSettings()
            providerMode = settings.selectedProviderMode
            editingProviderMode = settings.selectedProviderMode
            imageProcessingModeRawValue = LisdoSyncedSettings.normalizedImageProcessingModeRawValue(settings.imageProcessingModeRawValue)
            voiceProcessingModeRawValue = LisdoSyncedSettings.normalizedVoiceProcessingModeRawValue(settings.voiceProcessingModeRawValue)
            providerModeStatus = ""
            loadProviderFields(for: editingProviderMode)
        } catch {
            providerModeStatus = "Load failed: \(error.localizedDescription)"
            loadProviderFields(for: editingProviderMode)
        }
    }

    private func loadProviderFields(for mode: ProviderMode) {
        let settings = providerFactory.loadSettings(for: mode)
        endpoint = settings.endpointURL?.absoluteString ?? ""
        model = settings.model
        displayName = mode == .lisdoManaged ? "Lisdo" : settings.displayName ?? DraftProviderFactory.metadata(for: mode).displayName
        apiKey = ""
        bearerToken = settings.bearerToken ?? (mode == .lisdoManaged ? "dev-token" : "")

        if DraftProviderFactory.metadata(for: mode).requiresAPIKey {
            keyStatus = hasStoredAPIKey(for: mode)
                ? "Saved locally"
                : "No local key saved"
        } else {
            keyStatus = "No key required"
        }
    }

    private func saveProviderMode(_ mode: ProviderMode) {
        do {
            try syncedSettingsStore.updateProviderMode(mode)
            providerMode = mode
            editingProviderMode = mode
            loadProviderFields(for: mode)
            providerModeStatus = "Saved"
        } catch {
            providerModeStatus = "Save failed: \(error.localizedDescription)"
        }
    }

    private func saveImageProcessingMode(_ rawValue: String) {
        do {
            let settings = try syncedSettingsStore.updateImageProcessingModeRawValue(rawValue)
            imageProcessingModeRawValue = settings.imageProcessingModeRawValue
        } catch {
            providerModeStatus = "Save failed: \(error.localizedDescription)"
        }
    }

    private func saveVoiceProcessingMode(_ rawValue: String) {
        do {
            let settings = try syncedSettingsStore.updateVoiceProcessingModeRawValue(rawValue)
            voiceProcessingModeRawValue = settings.voiceProcessingModeRawValue
        } catch {
            providerModeStatus = "Save failed: \(error.localizedDescription)"
        }
    }

    private func saveProviderSettings() {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointURL = trimmedEndpoint.isEmpty ? nil : URL(string: trimmedEndpoint)
        if editingProviderMode != .macOnlyCLI, endpointURL == nil {
            keyStatus = "Invalid endpoint URL"
            return
        }

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let settings = DraftProviderLocalSettings(
                mode: editingProviderMode,
                endpointURL: endpointURL,
                model: trimmedModel.isEmpty ? editingMetadata.defaultModel : trimmedModel,
                displayName: editingProviderMode == .lisdoManaged ? "Lisdo" : trimmedDisplayName.isEmpty ? editingMetadata.displayName : trimmedDisplayName,
                requiresAPIKey: editingMetadata.requiresAPIKey,
                bearerToken: editingProviderMode == .lisdoManaged
                    ? managedBearerTokenForSaving
                    : nil
            )
            try credentialStore.saveProviderSettings(settings)

            if editingProviderMode == .openAICompatibleBYOK, let endpointURL {
                try credentialStore.saveOpenAICompatibleSettings(endpointURL: endpointURL, model: settings.model)
            }

            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedKey.isEmpty {
                try credentialStore.saveAPIKey(trimmedKey, for: editingProviderMode)
                if editingProviderMode == .openAICompatibleBYOK {
                    try credentialStore.saveOpenAICompatibleAPIKey(trimmedKey)
                }
                apiKey = ""
                keyStatus = "Saved locally"
            } else {
                keyStatus = editingMetadata.requiresAPIKey
                    ? (hasStoredAPIKey(for: editingProviderMode) ? "Local key unchanged" : "No local key saved")
                    : "No key required"
            }

            if editingProviderMode == .lisdoManaged, !canUseLisdoManagedProvider {
                providerModeStatus = "Lisdo settings saved. Choose a plan to use Lisdo."
            } else {
                saveProviderMode(editingProviderMode)
                activeSettingsSheet = .providerSelection
            }
        } catch {
            keyStatus = "Save failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func refreshLisdoBackendIfConfigured(silent: Bool) async {
        guard !isRefreshingBackend else { return }

        let settings = providerFactory.loadSettings(for: .lisdoManaged)
        guard let endpointURL = settings.endpointURL else {
            if !silent {
                backendRefreshStatus = "Add a Lisdo endpoint before refreshing."
            }
            return
        }

        let token = (settings.bearerToken ?? "dev-token")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            if !silent {
                backendRefreshStatus = "Add a Lisdo bearer token before refreshing."
            }
            return
        }

        isRefreshingBackend = true
        defer { isRefreshingBackend = false }

        do {
            _ = try await entitlementStore.refreshFromBackend(baseURL: endpointURL, bearerToken: token)
            backendRefreshStatus = ""
        } catch {
            if !silent {
                backendRefreshStatus = "Lisdo refresh failed: \(error.localizedDescription)"
            }
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

    private var selectedMetadata: DraftProviderModeMetadata {
        DraftProviderFactory.metadata(for: providerMode)
    }

    private var editingMetadata: DraftProviderModeMetadata {
        DraftProviderFactory.metadata(for: editingProviderMode)
    }

    private var iCloudIssueDetail: String? {
        guard !iCloudSyncStatusMonitor.snapshot.isCloudBacked else { return nil }
        return iCloudSyncStatusMonitor.snapshot.detail
    }

    private var notificationIssueDetail: String? {
        guard notificationStatus.title == "Notifications unavailable" else { return nil }
        return notificationStatus.detail
    }

    private var isLisdoAccountSignedIn: Bool {
        accountSessionService.currentLisdoBearerToken() != nil
    }

    private var lisdoAccountDetailText: String {
        return "Sign in with Apple so Mac and iPhone can share plan and quota."
    }

    private var accountProfileName: String {
        if let name = accountSummary?.fullName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }

        if let email = accountSummary?.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty,
           let localPart = email.split(separator: "@").first, !localPart.isEmpty {
            return String(localPart)
        }

        let label = accountSummary?.displayLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let label, !label.isEmpty else {
            return "Lisdo User"
        }
        return label
    }

    private var accountProfileDetail: String? {
        let email = accountSummary?.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let email, !email.isEmpty, email != accountProfileName else { return nil }
        return email
    }

    private var accountAvatarInitial: String? {
        accountProfileName.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() }
    }

    private var quotaRemainingLabel: String {
        if entitlementStore.serverQuota != nil {
            if !planDisplaySnapshot.isFeatureEnabled(.lisdoManagedDrafts) {
                return "Not active"
            }
            if planDisplaySnapshot.quotaBalance.totalUnits == 0 {
                return "No usage left"
            }
            return "Included usage"
        }

        return entitlementStore.snapshot.isFeatureEnabled(.lisdoManagedDrafts)
            ? "Local preview"
            : "Not active"
    }

    private var planActionTitle: String {
        planDisplaySnapshot.tier == .free ? "Upgrade plan" : "Manage plan"
    }

    private var mockQuotaRemainingFraction: Double {
        let balance = planDisplaySnapshot.quotaBalance
        let monthlyUnits = balance.monthlyNonRolloverUnits
        guard monthlyUnits > 0 else { return 0.06 }
        let seed = (monthlyUnits % 19) + (balance.topUpRolloverUnits % 7) + 2
        return min(0.86, max(0.1, Double(seed) / 25.0))
    }

    private var quotaRemainingFraction: Double {
        entitlementStore.serverQuota?.remainingFraction ?? mockQuotaRemainingFraction
    }

    private var providerSummary: String {
        if providerMode == .lisdoManaged {
            return canUseLisdoManagedProvider
                ? "Lisdo uses the managed dev endpoint and still requires review."
                : lisdoManagedUnavailableSummary
        }
        if selectedMetadata.isNormallyMacLocal {
            return "Captures queue for Mac-local processing when supported."
        }
        if selectedMetadata.requiresAPIKey {
            return hasStoredAPIKey(for: providerMode)
                ? "API key is saved only on this device."
                : "Add a local API key before organizing drafts."
        }
        return "Configured locally on this device."
    }

    private var canUseLisdoManagedProvider: Bool {
        entitlementStore.effectiveSnapshot.consumingDraftUnits(1).isAllowed
    }

    private var planDisplaySnapshot: LisdoEntitlementSnapshot {
        entitlementStore.quotaPresentationSnapshot
    }

    private var planSourceLabel: String {
        entitlementStore.hasServerQuota ? "Server" : "Local dev"
    }

    private var lisdoManagedUnavailableSummary: String {
        let snapshot = entitlementStore.effectiveSnapshot
        if !snapshot.isFeatureEnabled(.lisdoManagedDrafts) {
            return entitlementStore.hasServerQuota
                ? "The backend account does not include Lisdo drafts. Refresh after purchase or choose a paid plan."
                : "Choose a plan before using Lisdo as the draft provider."
        }
        return "Lisdo quota is empty. Refresh Lisdo or choose a plan with more included usage."
    }

    private var configuredProviderModes: [ProviderMode] {
        DraftProviderFactory.supportedModes.filter { mode in
            mode != .lisdoManaged && isProviderConfigured(mode)
        }
    }

    private var firstProviderModeForConfiguration: ProviderMode {
        DraftProviderFactory.supportedModes.first { mode in
            mode != .lisdoManaged && !isProviderConfigured(mode)
        } ?? .openAICompatibleBYOK
    }

    private var managedBearerTokenForSaving: String {
        let trimmedToken = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedToken.isEmpty ? "dev-token" : trimmedToken
    }

    private func hasStoredAPIKey(for mode: ProviderMode) -> Bool {
        let existingKey = (try? credentialStore.readAPIKey(for: mode)) ?? (mode == .openAICompatibleBYOK ? (try? credentialStore.readOpenAICompatibleAPIKey()) : nil)
        return existingKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func isProviderConfigured(_ mode: ProviderMode) -> Bool {
        if mode == .macOnlyCLI {
            return preferenceStore.readMacOnlyCLISettings() != nil
                || credentialStore.readProviderSettings(for: mode) != nil
        }

        let metadata = DraftProviderFactory.metadata(for: mode)
        if metadata.requiresAPIKey {
            return hasStoredAPIKey(for: mode)
        }

        return credentialStore.readProviderSettings(for: mode) != nil
            || (mode == .openAICompatibleBYOK && credentialStore.readOpenAICompatibleSettings() != nil)
    }

    private func loadAccountSessionState() {
        accountSummary = accountSessionService.currentAccountSummary()
    }

    private func signOutLisdoAccount() {
        do {
            try accountSessionService.signOut()
            accountSummary = nil
            backendRefreshStatus = ""
            purchaseStatus = "Signed out."
            entitlementStore.clearServerSnapshot(resetTo: .free)
            if providerMode == .lisdoManaged {
                saveProviderMode(.openAICompatibleBYOK)
            } else {
                loadProviderSettings()
            }
        } catch {
            purchaseStatus = "Sign out failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func refreshLisdoAccountSummaryIfNeeded() async {
        guard isLisdoAccountSignedIn, accountSummary?.email == nil else { return }
        accountSummary = try? await accountSessionService.refreshAccountSummaryFromBackend()
    }

    private func providerDisplayName(for mode: ProviderMode) -> String {
        if mode == .lisdoManaged {
            return "Lisdo"
        }
        let savedName = providerFactory.loadSettings(for: mode).displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let savedName, !savedName.isEmpty {
            return savedName
        }
        return DraftProviderFactory.metadata(for: mode).displayName
    }

    private func planDescription(for tier: LisdoPlanTier) -> String {
        let snapshot = LisdoEntitlementSnapshot(tier: tier)
        let providerText = snapshot.isFeatureEnabled(.lisdoManagedDrafts)
            ? "Lisdo provider available"
            : "BYOK and Mac-local providers"
        let storageText = snapshot.isFeatureEnabled(.iCloudSync)
            ? "iCloud-backed storage"
            : "local-only storage"
        return "\(providerText), \(storageText)."
    }

    private func planPriceLabel(for tier: LisdoPlanTier) -> String {
        guard let productID = LisdoStoreProductID.productID(for: tier) else {
            return "Free"
        }
        if let product = storeKitService.products[productID.rawValue] {
            return product.displayPrice
        }
        switch tier {
        case .free:
            return "Free"
        case .starterTrial:
            return "$0.99"
        case .monthlyBasic:
            return "$4.99/mo"
        case .monthlyPlus:
            return "$9.99/mo"
        case .monthlyMax:
            return "$14.99/mo"
        }
    }

    private func beginAppleSignInAuthentication(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8)
            else {
                purchaseStatus = "Apple sign in did not return an identity token."
                return
            }
            let authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            let fullName = appleFullNameString(from: credential.fullName)
            Task { await authenticateLisdoAccount(identityToken: identityToken, authorizationCode: authorizationCode, fullName: fullName) }
        case .failure(let error):
            purchaseStatus = "Apple sign in failed: \(error.localizedDescription)"
        }
    }

    private func appleFullNameString(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatted = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return formatted.isEmpty ? nil : formatted
    }

    @MainActor
    private func authenticateLisdoAccount(identityToken: String, authorizationCode: String?, fullName: String?) async {
        guard !isAuthenticatingLisdoAccount else { return }
        isAuthenticatingLisdoAccount = true
        purchaseStatus = "Signing in to Lisdo..."
        defer { isAuthenticatingLisdoAccount = false }

        do {
            _ = try await accountSessionService.authenticateWithApple(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                fullName: fullName
            )
            loadAccountSessionState()
            loadProviderSettings()
            await refreshLisdoBackendIfConfigured(silent: true)
            purchaseStatus = "Signed in. Purchases can now sync plan and quota."
            let pendingProduct = pendingStoreProductAfterSignIn
            let shouldRestore = shouldRestorePurchasesAfterSignIn
            pendingStoreProductAfterSignIn = nil
            shouldRestorePurchasesAfterSignIn = false
            if let pendingProduct {
                activeSettingsSheet = .plan
                await purchaseStoreProduct(pendingProduct)
            } else if shouldRestore {
                activeSettingsSheet = .plan
                await restorePurchases()
            }
        } catch {
            purchaseStatus = "Apple sign in failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func selectOrPurchasePlan(_ tier: LisdoPlanTier) async {
        guard tier != .free else {
            if entitlementStore.hasServerQuota {
                purchaseStatus = "Downgrades are managed from your App Store subscription settings."
            } else {
                selectPlan(.free)
                purchaseStatus = "Free plan saved locally."
            }
            return
        }
        guard let productID = LisdoStoreProductID.productID(for: tier) else {
            return
        }
        await purchaseStoreProduct(productID)
    }

    @MainActor
    private func purchaseStoreProduct(_ productID: LisdoStoreProductID) async {
        guard accountSessionService.currentLisdoBearerToken() != nil else {
            presentAccountSignInSheet(for: productID)
            return
        }
        guard !isPurchasingOrRestoring else { return }

        isPurchasingOrRestoring = true
        purchaseStatus = "Opening App Store purchase..."
        defer { isPurchasingOrRestoring = false }

        do {
            let transaction = try await storeKitService.purchase(productID: productID)
            let response = try await accountSessionService.verifyStoreKitTransaction(
                storeKitService.verificationRequest(for: transaction)
            )
            entitlementStore.applyServerSnapshot(response.serverSnapshot(refreshedAt: Date()))
            await transaction.transaction.finish()
            applyPostPurchaseProviderSelection()
            purchaseStatus = "\(productID.fallbackDisplayName) is active. Quota refreshed."
            refreshICloudStatusAfterStorageChange()
        } catch LisdoStoreKitServiceError.purchaseCancelled {
            purchaseStatus = "Purchase cancelled."
        } catch LisdoStoreKitServiceError.productUnavailable(let unavailableProductID) {
            purchaseStatus = "Purchase unavailable: \(unavailableProductID). Check the App Store Connect product setup, then retry."
        } catch {
            purchaseStatus = "Purchase failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func restorePurchases() async {
        guard accountSessionService.currentLisdoBearerToken() != nil else {
            presentAccountSignInSheetForRestore()
            return
        }
        guard !isPurchasingOrRestoring else { return }

        isPurchasingOrRestoring = true
        purchaseStatus = "Restoring purchases..."
        defer { isPurchasingOrRestoring = false }

        do {
            let transactions = try await storeKitService.restoreVerifiedTransactions()
            guard !transactions.isEmpty else {
                purchaseStatus = "No active purchases were found."
                return
            }

            var restoredTier: LisdoPlanTier?
            for transaction in transactions {
                let response = try await accountSessionService.verifyStoreKitTransaction(
                    storeKitService.verificationRequest(for: transaction)
                )
                entitlementStore.applyServerSnapshot(response.serverSnapshot(refreshedAt: Date()))
                restoredTier = response.quota.entitlementSnapshot(entitlements: response.entitlements).tier
            }
            applyPostPurchaseProviderSelection()
            purchaseStatus = "Purchases restored. Quota refreshed."
            if restoredTier != nil {
                refreshICloudStatusAfterStorageChange()
            }
        } catch {
            purchaseStatus = "Restore failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func presentAccountSignInSheet(for productID: LisdoStoreProductID) {
        pendingStoreProductAfterSignIn = productID
        shouldRestorePurchasesAfterSignIn = false
        purchaseStatus = "Sign in with Apple to continue \(productID.fallbackDisplayName)."
        activeSettingsSheet = .accountSignIn
    }

    @MainActor
    private func presentAccountSignInSheetForRestore() {
        pendingStoreProductAfterSignIn = nil
        shouldRestorePurchasesAfterSignIn = true
        purchaseStatus = "Sign in with Apple before restoring purchases."
        activeSettingsSheet = .accountSignIn
    }

    private func applyPostPurchaseProviderSelection() {
        guard entitlementStore.effectiveSnapshot.isFeatureEnabled(.lisdoManagedDrafts) else { return }
        saveProviderMode(.lisdoManaged)
    }

    private func refreshICloudStatusAfterStorageChange() {
        iCloudSyncStatusMonitor.refresh()
    }

    private func providerSelectionDescription(for mode: ProviderMode, isLocked: Bool) -> String {
        if mode == .lisdoManaged {
            return isLocked
                ? "Requires Starter Trial or a monthly plan."
                : "Uses the Lisdo managed dev endpoint."
        }
        if DraftProviderFactory.metadata(for: mode).isNormallyMacLocal {
            return "Saved locally for Mac processing."
        }
        if DraftProviderFactory.metadata(for: mode).requiresAPIKey {
            return "Configured with a local Keychain API key."
        }
        return "Configured locally on this device."
    }

    private func apiKeyLocalStorageCopy(for mode: ProviderMode) -> String {
        switch mode {
        case .openAICompatibleBYOK, .minimax, .anthropic, .gemini, .openRouter:
            return "Hosted BYOK API keys are saved only in this device's Keychain."
        case .localModel:
            return "Optional local-model API keys stay in this device's Keychain."
        case .ollama, .lmStudio:
            return "No hosted BYOK key is required for this local provider."
        case .lisdoManaged:
            return "The dev token is saved only in local settings."
        case .macOnlyCLI:
            return "Mac-only CLI credentials are not configured on iPhone."
        }
    }

    private func selectPlan(_ tier: LisdoPlanTier) {
        _ = entitlementStore.updateSelectedTier(tier)

        if tier == .free, providerMode == .lisdoManaged {
            saveProviderMode(.openAICompatibleBYOK)
        } else if tier != .free {
            saveProviderMode(.lisdoManaged)
        }

        refreshICloudStatusAfterStorageChange()
    }

    private func selectProvider(_ mode: ProviderMode) {
        guard mode != .lisdoManaged || canUseLisdoManagedProvider else {
            providerModeStatus = "Choose a plan before using Lisdo."
            activeSettingsSheet = .plan
            return
        }

        saveProviderMode(mode)
        activeSettingsSheet = nil
    }

    private var syncedSettingsStore: LisdoSyncedSettingsStore {
        LisdoSyncedSettingsStore(context: modelContext)
    }
}

private enum YouSettingsSheet: Identifiable, Equatable {
    case plan
    case accountSignIn
    case providerSelection
    case providerConfiguration

    var id: String {
        switch self {
        case .plan:
            return "plan"
        case .accountSignIn:
            return "account-sign-in"
        case .providerSelection:
            return "provider-selection"
        case .providerConfiguration:
            return "provider-configuration"
        }
    }
}

private struct ImageProcessingModeSelector: View {
    @Binding var selection: String

    var body: some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            LiquidGlassImageProcessingSelector(selection: $selection)
        } else {
            fallbackSelector
        }
#else
        fallbackSelector
#endif
    }

    private var fallbackSelector: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                fallbackButton(for: option)
            }
        }
        .padding(4)
        .background(LisdoTheme.surface3.opacity(0.72), in: Capsule())
        .overlay {
            Capsule()
                .stroke(LisdoTheme.divider.opacity(0.7), lineWidth: 1)
        }
    }

    private var options: [(value: String, title: String)] {
        LisdoImageProcessingMode.allCases.map { mode in
            (value: mode.rawValue, title: title(for: mode))
        }
    }

    private func title(for mode: LisdoImageProcessingMode) -> String {
        switch mode {
        case .visionOCR:
            return "OCR"
        case .directLLM:
            return "Image LLM"
        }
    }

    private func fallbackButton(for option: (value: String, title: String)) -> some View {
        let isSelected = selection == option.value

        return Button {
            selection = option.value
        } label: {
            Text(option.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .foregroundStyle(isSelected ? LisdoTheme.ink1 : LisdoTheme.ink3)
                .background(
                    isSelected ? LisdoTheme.ink7 : Color.clear,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#if compiler(>=6.2)
@available(iOS 26.0, *)
private struct LiquidGlassImageProcessingSelector: View {
    @Binding var selection: String

    private let options: [(value: String, title: String)] = LisdoImageProcessingMode.allCases.map { mode in
        switch mode {
        case .visionOCR:
            return (value: mode.rawValue, title: "OCR")
        case .directLLM:
            return (value: mode.rawValue, title: "Image LLM")
        }
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    selectorButton(for: option)
                }
            }
            .padding(4)
            .background(LisdoTheme.surface3.opacity(0.42), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(LisdoTheme.divider.opacity(0.55), lineWidth: 1)
            }
            .glassEffect(.regular.tint(LisdoTheme.surface.opacity(0.28)), in: Capsule())
        }
    }

    private func selectorButton(for option: (value: String, title: String)) -> some View {
        let isSelected = selection == option.value

        return Button {
            selection = option.value
        } label: {
            Text(option.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .foregroundStyle(isSelected ? LisdoTheme.ink1 : LisdoTheme.ink3)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                Capsule()
                    .fill(LisdoTheme.ink7.opacity(0.96))
                    .overlay {
                        Capsule()
                            .stroke(LisdoTheme.divider.opacity(0.45), lineWidth: 0.8)
                    }
                    .glassEffect(.regular.tint(LisdoTheme.ink7.opacity(0.2)).interactive(), in: Capsule())
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
