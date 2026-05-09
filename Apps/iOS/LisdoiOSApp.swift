import LisdoCore
import SwiftData
import SwiftUI

@main
struct LisdoiOSApp: App {
    private let modelContainerResult: LisdoiOSModelContainer.Result
    @StateObject private var iCloudSyncStatusMonitor: LisdoICloudSyncStatusMonitor

    init() {
        let result = LisdoiOSModelContainer.make()
        self.modelContainerResult = result
        self._iCloudSyncStatusMonitor = StateObject(
            wrappedValue: LisdoICloudSyncStatusMonitor(
                persistenceMode: result.persistenceMode,
                fallbackErrorDescription: result.fallbackErrorDescription
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            LisdoRootView()
                .modelContainer(modelContainerResult.container)
                .environmentObject(iCloudSyncStatusMonitor)
        }
    }
}

private enum LisdoiOSModelContainer {
    struct Result {
        var container: ModelContainer
        var persistenceMode: LisdoCloudPersistenceMode
        var fallbackErrorDescription: String?
    }

    static func make() -> Result {
        do {
            return Result(
                container: try LisdoModelContainerFactory.makeCloudKitContainer(),
                persistenceMode: .cloudKit,
                fallbackErrorDescription: nil
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
                    fallbackErrorDescription: fallbackErrorDescription
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
                        fallbackErrorDescription: error.localizedDescription
                    )
                } catch {
                    fatalError("Unable to create Lisdo iOS model container: \(error)")
                }
            }
        }
    }
}
