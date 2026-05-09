import CloudKit
import Combine
import Foundation

public enum LisdoCloudPersistenceMode: Equatable, Sendable {
    case cloudKit
    case localFallback
    case inMemoryFallback
}

public struct LisdoICloudSyncStatusSnapshot: Equatable, Sendable {
    public var title: String
    public var detail: String?
    public var systemImage: String
    public var isCloudBacked: Bool

    public init(
        title: String,
        detail: String? = nil,
        systemImage: String,
        isCloudBacked: Bool
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.isCloudBacked = isCloudBacked
    }
}

@MainActor
public final class LisdoICloudSyncStatusMonitor: ObservableObject {
    @Published public private(set) var snapshot: LisdoICloudSyncStatusSnapshot

    private let containerIdentifier: String
    private let persistenceMode: LisdoCloudPersistenceMode
    private let fallbackErrorDescription: String?
    private var refreshTask: Task<Void, Never>?

    public init(
        containerIdentifier: String = LisdoModelContainerFactory.cloudKitContainerIdentifier,
        persistenceMode: LisdoCloudPersistenceMode,
        fallbackErrorDescription: String? = nil
    ) {
        self.containerIdentifier = containerIdentifier
        self.persistenceMode = persistenceMode
        self.fallbackErrorDescription = fallbackErrorDescription
        self.snapshot = Self.initialSnapshot(
            persistenceMode: persistenceMode,
            fallbackErrorDescription: fallbackErrorDescription
        )
    }

    deinit {
        refreshTask?.cancel()
    }

    public func refresh() {
        refreshTask?.cancel()
        snapshot = Self.initialSnapshot(
            persistenceMode: persistenceMode,
            fallbackErrorDescription: fallbackErrorDescription
        )

        guard persistenceMode == .cloudKit else { return }

        let containerIdentifier = containerIdentifier
        refreshTask = Task { [weak self] in
            do {
                let accountStatus = try await Self.fetchAccountStatus(containerIdentifier: containerIdentifier)
                guard !Task.isCancelled else { return }
                self?.apply(accountStatus)
            } catch {
                guard !Task.isCancelled else { return }
                self?.applyAccountError(error)
            }
        }
    }

    private static func initialSnapshot(
        persistenceMode: LisdoCloudPersistenceMode,
        fallbackErrorDescription: String?
    ) -> LisdoICloudSyncStatusSnapshot {
        switch persistenceMode {
        case .cloudKit:
            return LisdoICloudSyncStatusSnapshot(
                title: "Checking iCloud",
                detail: "Verifying account access.",
                systemImage: "icloud",
                isCloudBacked: true
            )
        case .localFallback:
            return LisdoICloudSyncStatusSnapshot(
                title: "Local only",
                detail: fallbackErrorDescription.map { "CloudKit unavailable: \($0)" },
                systemImage: "icloud.slash",
                isCloudBacked: false
            )
        case .inMemoryFallback:
            return LisdoICloudSyncStatusSnapshot(
                title: "Memory only",
                detail: fallbackErrorDescription.map { "Persistent store unavailable: \($0)" },
                systemImage: "externaldrive.badge.xmark",
                isCloudBacked: false
            )
        }
    }

    private static func fetchAccountStatus(containerIdentifier: String) async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            CKContainer(identifier: containerIdentifier).accountStatus { accountStatus, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: accountStatus)
                }
            }
        }
    }

    private func apply(_ accountStatus: CKAccountStatus) {
        switch accountStatus {
        case .available:
            snapshot = LisdoICloudSyncStatusSnapshot(
                title: "iCloud sync active",
                detail: "CloudKit account is available.",
                systemImage: "icloud",
                isCloudBacked: true
            )
        case .noAccount:
            snapshot = LisdoICloudSyncStatusSnapshot(
                title: "Sign in to iCloud",
                detail: "Lisdo is using a CloudKit store, but no iCloud account is available.",
                systemImage: "person.crop.circle.badge.exclamationmark",
                isCloudBacked: false
            )
        case .restricted:
            snapshot = LisdoICloudSyncStatusSnapshot(
                title: "iCloud restricted",
                detail: "This account or device is restricted from iCloud.",
                systemImage: "lock.icloud",
                isCloudBacked: false
            )
        case .couldNotDetermine:
            snapshot = LisdoICloudSyncStatusSnapshot(
                title: "iCloud unknown",
                detail: "CloudKit could not determine account status.",
                systemImage: "icloud.and.arrow.trianglehead.2.clockwise.rotate.90",
                isCloudBacked: false
            )
        case .temporarilyUnavailable:
            snapshot = LisdoICloudSyncStatusSnapshot(
                title: "iCloud unavailable",
                detail: "CloudKit account status is temporarily unavailable.",
                systemImage: "icloud.slash",
                isCloudBacked: false
            )
        @unknown default:
            snapshot = LisdoICloudSyncStatusSnapshot(
                title: "iCloud unknown",
                detail: "CloudKit returned an unknown account status.",
                systemImage: "icloud.and.arrow.trianglehead.2.clockwise.rotate.90",
                isCloudBacked: false
            )
        }
    }

    private func applyAccountError(_ error: Error) {
        snapshot = LisdoICloudSyncStatusSnapshot(
            title: "iCloud check failed",
            detail: error.localizedDescription,
            systemImage: "exclamationmark.icloud",
            isCloudBacked: false
        )
    }
}
