import AppKit
import Carbon
import LisdoCore
import OSLog
import SwiftData
import SwiftUI

@main
struct LisdoMacApp: App {
    @NSApplicationDelegateAdaptor(LisdoMacAppDelegate.self) private var appDelegate
    @StateObject private var modelContainerStore: LisdoMacModelContainerStore
    @StateObject private var iCloudSyncStatusMonitor: LisdoICloudSyncStatusMonitor
    @StateObject private var entitlementStore: LisdoEntitlementStore
    @StateObject private var sparkleUpdater: LisdoMacSparkleUpdater

    init() {
        let entitlementStore = LisdoEntitlementStore()
        let modelContainerStore = LisdoMacModelContainerStore(entitlements: entitlementStore.snapshot)
        let result = modelContainerStore.result
        self._modelContainerStore = StateObject(wrappedValue: modelContainerStore)
        self._entitlementStore = StateObject(wrappedValue: entitlementStore)
        self._iCloudSyncStatusMonitor = StateObject(
            wrappedValue: LisdoICloudSyncStatusMonitor(
                persistenceMode: result.persistenceMode,
                fallbackErrorDescription: result.fallbackErrorDescription
            )
        )
        self._sparkleUpdater = StateObject(wrappedValue: LisdoMacSparkleUpdater())
    }

    var body: some Scene {
        Window("Lisdo", id: "main") {
            LisdoMacRootView()
                .id(modelContainerStore.generation)
                .modelContainer(modelContainerStore.result.container)
                .environmentObject(iCloudSyncStatusMonitor)
                .environmentObject(entitlementStore)
                .frame(minWidth: 880, minHeight: 620)
                .onChange(of: entitlementStore.snapshot) { _, nextSnapshot in
                    modelContainerStore.reconcile(
                        entitlements: nextSnapshot,
                        statusMonitor: iCloudSyncStatusMonitor
                    )
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    sparkleUpdater.checkForUpdates()
                }
                .disabled(!sparkleUpdater.canCheckForUpdates)
            }
        }

        MenuBarExtra("Lisdo", systemImage: "tray.full") {
            LisdoMenuBarCaptureView()
                .id(modelContainerStore.generation)
                .modelContainer(modelContainerStore.result.container)
                .environmentObject(entitlementStore)
                .onChange(of: entitlementStore.snapshot) { _, nextSnapshot in
                    modelContainerStore.reconcile(
                        entitlements: nextSnapshot,
                        statusMonitor: iCloudSyncStatusMonitor
                    )
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            LisdoMacProviderSettingsView()
                .id(modelContainerStore.generation)
                .modelContainer(modelContainerStore.result.container)
                .environmentObject(sparkleUpdater)
                .environmentObject(iCloudSyncStatusMonitor)
                .environmentObject(entitlementStore)
                .frame(width: 560, height: 580)
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
private final class LisdoMacModelContainerStore: ObservableObject {
    @Published private(set) var result: LisdoMacModelContainer.Result
    @Published private(set) var generation = UUID()

    init(entitlements: LisdoEntitlementSnapshot) {
        self.result = LisdoMacModelContainer.make(entitlements: entitlements)
    }

    func reconcile(
        entitlements: LisdoEntitlementSnapshot,
        statusMonitor: LisdoICloudSyncStatusMonitor
    ) {
        let nextRequiresCloudKit = entitlements.isFeatureEnabled(.iCloudSync)
        guard result.requiresCloudKit != nextRequiresCloudKit else { return }

        result = LisdoMacModelContainer.make(entitlements: entitlements)
        _ = try? LisdoSyncedSettingsStore(context: result.container.mainContext)
            .reconcileProviderMode(for: entitlements)
        generation = UUID()
        statusMonitor.update(
            persistenceMode: result.persistenceMode,
            fallbackErrorDescription: result.fallbackErrorDescription
        )
    }
}

final class LisdoMacAppDelegate: NSObject, NSApplicationDelegate {
    private let quickCaptureHotKeyRegistrar = MacGlobalHotKeyRegistrar(identifier: 1)
    private let selectedAreaHotKeyRegistrar = MacGlobalHotKeyRegistrar(identifier: 2)
    private var hotKeyObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        registerGlobalHotKeys()
        hotKeyObserver = NotificationCenter.default.addObserver(
            forName: LisdoMacNotifications.hotKeysChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.registerGlobalHotKeys()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        quickCaptureHotKeyRegistrar.unregister()
        selectedAreaHotKeyRegistrar.unregister()
        if let hotKeyObserver {
            NotificationCenter.default.removeObserver(hotKeyObserver)
        }
    }

    private func registerGlobalHotKeys() {
        quickCaptureHotKeyRegistrar.unregister()
        selectedAreaHotKeyRegistrar.unregister()

        var statusMessages: [String] = []
        register(
            action: .quickCapture,
            registrar: quickCaptureHotKeyRegistrar,
            successLabel: "Quick Capture"
        ) {
            NotificationCenter.default.post(name: LisdoMacNotifications.openCapture, object: nil)
        } status: { message in
            statusMessages.append(message)
        }

        register(
            action: .selectedArea,
            registrar: selectedAreaHotKeyRegistrar,
            successLabel: "Selected Area"
        ) {
            NotificationCenter.default.post(name: LisdoMacNotifications.selectScreenArea, object: nil)
        } status: { message in
            statusMessages.append(message)
        }

        UserDefaults.standard.set(
            statusMessages.isEmpty ? "Global hotkeys are off." : statusMessages.joined(separator: " "),
            forKey: LisdoMacNotifications.hotKeyStatusDefaultsKey
        )
    }

    private func register(
        action: LisdoMacHotKeyAction,
        registrar: MacGlobalHotKeyRegistrar,
        successLabel: String,
        callback: @escaping @Sendable () -> Void,
        status: (String) -> Void
    ) {
        let preset = LisdoMacHotKeyPreferences.preset(for: action)
        guard let hotKey = preset.hotKey else {
            status("\(successLabel) hotkey is off.")
            return
        }

        do {
            try registrar.register(hotKey: hotKey, callback: callback)
            status("\(successLabel): \(preset.title).")
        } catch {
            status("\(successLabel) hotkey failed: \(error.localizedDescription)")
        }
    }
}

private enum LisdoMacModelContainer {
    struct Result {
        var container: ModelContainer
        var persistenceMode: LisdoCloudPersistenceMode
        var fallbackErrorDescription: String?
        var requiresCloudKit: Bool
    }

    private static let logger = Logger(subsystem: "com.yiwenwu.Lisdo.macOS", category: "model-container")

    static func make(entitlements: LisdoEntitlementSnapshot) -> Result {
        guard entitlements.isFeatureEnabled(.iCloudSync) else {
            do {
                let container = try LisdoModelContainerFactory.makeLocalPersistentContainer(name: "LisdoMacEntitlementLocal")
                return Result(
                    container: container,
                    persistenceMode: .entitlementLocal,
                    fallbackErrorDescription: nil,
                    requiresCloudKit: false
                )
            } catch {
                fatalError("Unable to create Lisdo local SwiftData model container: \(error)")
            }
        }

        do {
            let container = try LisdoModelContainerFactory.makeCloudKitContainer()
            return Result(
                container: container,
                persistenceMode: .cloudKit,
                fallbackErrorDescription: nil,
                requiresCloudKit: true
            )
        } catch {
            logger.error("Falling back to an isolated macOS SwiftData container: \(String(describing: error), privacy: .public)")
            let fallbackErrorDescription = error.localizedDescription

            do {
                let schema = LisdoModelContainerFactory.schema
                let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
                let container = try ModelContainer(for: schema, configurations: [configuration])
                return Result(
                    container: container,
                    persistenceMode: .localFallback,
                    fallbackErrorDescription: fallbackErrorDescription,
                    requiresCloudKit: true
                )
            } catch {
                fatalError("Unable to create Lisdo SwiftData model container: \(error)")
            }
        }
    }
}
