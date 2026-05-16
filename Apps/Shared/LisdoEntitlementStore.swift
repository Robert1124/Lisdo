import Combine
import Foundation
import LisdoCore

@MainActor
public final class LisdoEntitlementStore: ObservableObject {
    @Published public private(set) var snapshot: LisdoEntitlementSnapshot
    @Published public private(set) var serverSnapshot: LisdoServerEntitlementSnapshot?

    nonisolated public static let iCloudPlanChangeReloadNote = "Lisdo switches between local-only and iCloud-backed storage immediately after plan changes."

    private let userDefaults: UserDefaults
    private var quotaUpdateObserver: NSObjectProtocol?

    private enum DefaultsKey {
        static let selectedPlanTier = "lisdo.entitlements.dev-selected-plan-tier"
        static let serverSnapshot = "lisdo.entitlements.server-snapshot"
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.snapshot = Self.readLocalSnapshot(userDefaults: userDefaults)
        self.serverSnapshot = Self.readServerSnapshot(userDefaults: userDefaults)
        startObservingManagedQuotaUpdates()
    }

    deinit {
        if let quotaUpdateObserver {
            NotificationCenter.default.removeObserver(quotaUpdateObserver)
        }
    }

    public var selectedTier: LisdoPlanTier {
        snapshot.tier
    }

    public var quotaPresentationSnapshot: LisdoEntitlementSnapshot {
        serverSnapshot?.snapshot ?? snapshot
    }

    public var quotaPresentationSource: LisdoEntitlementQuotaPresentationSource {
        serverSnapshot == nil ? .localPreview : .server
    }

    public var serverQuota: LisdoBackendQuota? {
        serverSnapshot?.quota
    }

    public var hasServerQuota: Bool {
        serverSnapshot != nil
    }

    public var effectiveSnapshot: LisdoEntitlementSnapshot {
        quotaPresentationSnapshot
    }

    @discardableResult
    public func updateSelectedTier(_ tier: LisdoPlanTier) -> LisdoEntitlementSnapshot {
        userDefaults.set(tier.rawValue, forKey: DefaultsKey.selectedPlanTier)
        snapshot = LisdoEntitlementSnapshot(tier: tier)
        return snapshot
    }

    public func refresh() {
        snapshot = Self.readLocalSnapshot(userDefaults: userDefaults)
        serverSnapshot = Self.readServerSnapshot(userDefaults: userDefaults)
    }

    public func clearServerSnapshot(resetTo tier: LisdoPlanTier = .free) {
        userDefaults.removeObject(forKey: DefaultsKey.serverSnapshot)
        userDefaults.set(tier.rawValue, forKey: DefaultsKey.selectedPlanTier)
        snapshot = LisdoEntitlementSnapshot(tier: tier)
        serverSnapshot = nil
    }

    @discardableResult
    public func refreshFromBackend(baseURL: URL, bearerToken: String) async throws -> LisdoServerEntitlementSnapshot {
        let client = LisdoBackendClient(baseURL: baseURL, bearerToken: bearerToken)
        let bootstrap = try await client.bootstrap()
        let serverSnapshot = bootstrap.serverSnapshot(refreshedAt: Date())
        applyServerSnapshot(serverSnapshot)
        return serverSnapshot
    }

    public func applyServerSnapshot(_ newServerSnapshot: LisdoServerEntitlementSnapshot) {
        if let data = try? JSONEncoder().encode(newServerSnapshot) {
            userDefaults.set(data, forKey: DefaultsKey.serverSnapshot)
        }
        userDefaults.set(newServerSnapshot.snapshot.tier.rawValue, forKey: DefaultsKey.selectedPlanTier)
        snapshot = LisdoEntitlementSnapshot(tier: newServerSnapshot.snapshot.tier)
        serverSnapshot = newServerSnapshot
    }

    nonisolated public static func currentSnapshot(userDefaults: UserDefaults = .standard) -> LisdoEntitlementSnapshot {
        readServerSnapshot(userDefaults: userDefaults)?.snapshot ?? readLocalSnapshot(userDefaults: userDefaults)
    }

    nonisolated public static func currentLocalSnapshot(userDefaults: UserDefaults = .standard) -> LisdoEntitlementSnapshot {
        readLocalSnapshot(userDefaults: userDefaults)
    }

    private func startObservingManagedQuotaUpdates() {
        quotaUpdateObserver = NotificationCenter.default.addObserver(
            forName: .lisdoManagedQuotaDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let update = notification.object as? LisdoManagedQuotaUpdate else {
                return
            }

            Task { @MainActor [weak self] in
                self?.applyManagedQuotaUpdate(update)
            }
        }
    }

    private func applyManagedQuotaUpdate(_ update: LisdoManagedQuotaUpdate) {
        let serverSnapshot = LisdoServerEntitlementSnapshot(
            quota: update.quota,
            entitlements: self.serverSnapshot?.entitlements,
            refreshedAt: update.receivedAt,
            source: .quotaUpdate
        )
        applyServerSnapshot(serverSnapshot)
    }

    nonisolated private static func readLocalSnapshot(userDefaults: UserDefaults) -> LisdoEntitlementSnapshot {
        let rawTier = userDefaults.string(forKey: DefaultsKey.selectedPlanTier)
        let tier = rawTier.flatMap(LisdoPlanTier.init(rawValue:)) ?? .free
        return LisdoEntitlementSnapshot(tier: tier)
    }

    nonisolated private static func readServerSnapshot(userDefaults: UserDefaults) -> LisdoServerEntitlementSnapshot? {
        guard let data = userDefaults.data(forKey: DefaultsKey.serverSnapshot) else {
            return nil
        }
        return try? JSONDecoder().decode(LisdoServerEntitlementSnapshot.self, from: data)
    }
}

public enum LisdoEntitlementQuotaPresentationSource: String, Codable, Equatable, Sendable {
    case localPreview
    case server
}

public extension LisdoPlanTier {
    var lisdoDisplayName: String {
        switch self {
        case .free:
            return "Free"
        case .starterTrial:
            return "Starter Trial"
        case .monthlyBasic:
            return "Monthly Basic"
        case .monthlyPlus:
            return "Monthly Plus"
        case .monthlyMax:
            return "Monthly Max"
        }
    }
}
