import AppKit
import Carbon
import LisdoCore
import OSLog
import SwiftData
import SwiftUI

@main
struct LisdoMacApp: App {
    @NSApplicationDelegateAdaptor(LisdoMacAppDelegate.self) private var appDelegate
    private let modelContainerResult: LisdoMacModelContainer.Result
    @StateObject private var iCloudSyncStatusMonitor: LisdoICloudSyncStatusMonitor

    init() {
        let result = LisdoMacModelContainer.make()
        self.modelContainerResult = result
        self._iCloudSyncStatusMonitor = StateObject(
            wrappedValue: LisdoICloudSyncStatusMonitor(
                persistenceMode: result.persistenceMode,
                fallbackErrorDescription: result.fallbackErrorDescription
            )
        )
    }

    var body: some Scene {
        Window("Lisdo", id: "main") {
            LisdoMacRootView()
                .modelContainer(modelContainerResult.container)
                .environmentObject(iCloudSyncStatusMonitor)
                .frame(minWidth: 880, minHeight: 620)
        }

        MenuBarExtra("Lisdo", systemImage: "tray.full") {
            LisdoMenuBarCaptureView()
                .modelContainer(modelContainerResult.container)
        }
        .menuBarExtraStyle(.window)

        Settings {
            LisdoMacProviderSettingsView()
                .frame(width: 460)
        }
    }
}

final class LisdoMacAppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeyRegistrar = MacGlobalHotKeyRegistrar()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        registerGlobalHotKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyRegistrar.unregister()
    }

    private func registerGlobalHotKey() {
        do {
            try hotKeyRegistrar.register(
                hotKey: MacGlobalHotKey(
                    keyCode: 49,
                    modifiers: UInt32(cmdKey | shiftKey)
                ),
                callback: {
                    NotificationCenter.default.post(name: LisdoMacNotifications.openCapture, object: nil)
                }
            )
            UserDefaults.standard.set(
                "Global hotkey ready: Command-Shift-Space.",
                forKey: LisdoMacNotifications.hotKeyStatusDefaultsKey
            )
        } catch {
            UserDefaults.standard.set(
                "Global hotkey could not be registered: \(error.localizedDescription)",
                forKey: LisdoMacNotifications.hotKeyStatusDefaultsKey
            )
        }
    }
}

private enum LisdoMacModelContainer {
    struct Result {
        var container: ModelContainer
        var persistenceMode: LisdoCloudPersistenceMode
        var fallbackErrorDescription: String?
    }

    private static let logger = Logger(subsystem: "com.yiwenwu.Lisdo.macOS", category: "model-container")

    static func make() -> Result {
        do {
            let container = try LisdoModelContainerFactory.makeCloudKitContainer()
            return Result(
                container: container,
                persistenceMode: .cloudKit,
                fallbackErrorDescription: nil
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
                    fallbackErrorDescription: fallbackErrorDescription
                )
            } catch {
                fatalError("Unable to create Lisdo SwiftData model container: \(error)")
            }
        }
    }
}
