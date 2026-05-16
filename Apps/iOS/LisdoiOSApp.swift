import LisdoCore
import SwiftData
import SwiftUI

@main
struct LisdoiOSApp: App {
    @StateObject private var modelContainerStore: LisdoiOSModelContainerStore
    @StateObject private var iCloudSyncStatusMonitor: LisdoICloudSyncStatusMonitor
    @StateObject private var entitlementStore: LisdoEntitlementStore
    @StateObject private var storeKitService: LisdoStoreKitService

    init() {
        let entitlementStore = LisdoEntitlementStore()
        let modelContainerStore = LisdoiOSModelContainerStore(entitlements: entitlementStore.snapshot)
        let result = modelContainerStore.result
        self._modelContainerStore = StateObject(wrappedValue: modelContainerStore)
        self._entitlementStore = StateObject(wrappedValue: entitlementStore)
        self._iCloudSyncStatusMonitor = StateObject(
            wrappedValue: LisdoICloudSyncStatusMonitor(
                persistenceMode: result.persistenceMode,
                fallbackErrorDescription: result.fallbackErrorDescription
            )
        )
        self._storeKitService = StateObject(wrappedValue: LisdoStoreKitService())
    }

    var body: some Scene {
        WindowGroup {
            LisdoRootView()
                .id(modelContainerStore.generation)
                .modelContainer(modelContainerStore.result.container)
                .environmentObject(iCloudSyncStatusMonitor)
                .environmentObject(entitlementStore)
                .environmentObject(storeKitService)
                .onAppear {
                    storeKitService.startTransactionUpdatesListener { response in
                        entitlementStore.applyServerSnapshot(response.serverSnapshot(refreshedAt: Date()))
                        iCloudSyncStatusMonitor.refresh()
                    }
                }
                .onChange(of: entitlementStore.snapshot) { _, nextSnapshot in
                    modelContainerStore.reconcile(
                        entitlements: nextSnapshot,
                        statusMonitor: iCloudSyncStatusMonitor
                    )
                }
        }
    }
}

@MainActor
private final class LisdoiOSModelContainerStore: ObservableObject {
    @Published private(set) var result: LisdoiOSModelContainer.Result
    @Published private(set) var generation = UUID()

    init(entitlements: LisdoEntitlementSnapshot) {
        self.result = LisdoiOSModelContainer.make(entitlements: entitlements)
    }

    func reconcile(
        entitlements: LisdoEntitlementSnapshot,
        statusMonitor: LisdoICloudSyncStatusMonitor
    ) {
        let nextRequiresCloudKit = entitlements.isFeatureEnabled(.iCloudSync)
        guard result.requiresCloudKit != nextRequiresCloudKit else { return }

        result = LisdoiOSModelContainer.make(entitlements: entitlements)
        _ = try? LisdoSyncedSettingsStore(context: result.container.mainContext)
            .reconcileProviderMode(for: entitlements)
        generation = UUID()
        statusMonitor.update(
            persistenceMode: result.persistenceMode,
            fallbackErrorDescription: result.fallbackErrorDescription
        )
    }
}

private enum LisdoiOSModelContainer {
    struct Result {
        var container: ModelContainer
        var persistenceMode: LisdoCloudPersistenceMode
        var fallbackErrorDescription: String?
        var requiresCloudKit: Bool
    }

    static func make(entitlements: LisdoEntitlementSnapshot) -> Result {
        guard entitlements.isFeatureEnabled(.iCloudSync) else {
            do {
                return Result(
                    container: try LisdoModelContainerFactory.makeLocalPersistentContainer(name: "LisdoiOSEntitlementLocal"),
                    persistenceMode: .entitlementLocal,
                    fallbackErrorDescription: nil,
                    requiresCloudKit: false
                )
            } catch {
                let schema = LisdoModelContainerFactory.schema
                let fallback = ModelConfiguration(
                    "LisdoiOSEntitlementInMemoryFallback",
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
                do {
                    return Result(
                        container: try ModelContainer(for: schema, configurations: [fallback]),
                        persistenceMode: .inMemoryFallback,
                        fallbackErrorDescription: error.localizedDescription,
                        requiresCloudKit: false
                    )
                } catch {
                    fatalError("Unable to create Lisdo iOS local model container: \(error)")
                }
            }
        }

        do {
            return Result(
                container: try LisdoModelContainerFactory.makeCloudKitContainer(),
                persistenceMode: .cloudKit,
                fallbackErrorDescription: nil,
                requiresCloudKit: true
            )
        } catch {
            let fallbackErrorDescription = error.localizedDescription
            let schema = LisdoModelContainerFactory.schema
            let configuration = ModelConfiguration(
                "LisdoiOSFallback",
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )

            do {
                return Result(
                    container: try ModelContainer(for: schema, configurations: [configuration]),
                    persistenceMode: .localFallback,
                    fallbackErrorDescription: fallbackErrorDescription,
                    requiresCloudKit: true
                )
            } catch {
                let fallback = ModelConfiguration(
                    "LisdoiOSInMemoryFallback",
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
                do {
                    return Result(
                        container: try ModelContainer(for: schema, configurations: [fallback]),
                        persistenceMode: .inMemoryFallback,
                        fallbackErrorDescription: error.localizedDescription,
                        requiresCloudKit: true
                    )
                } catch {
                    fatalError("Unable to create Lisdo iOS model container: \(error)")
                }
            }
        }
    }
}
