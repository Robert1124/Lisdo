import Combine
import Foundation
import Sparkle

@MainActor
final class LisdoMacSparkleUpdater: ObservableObject {
    @Published private(set) var statusMessage: String
    @Published private(set) var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController?

    init(bundle: Bundle = .main) {
        guard Self.hasConfiguredPublicEDKey(in: bundle) else {
            updaterController = nil
            statusMessage = "Updates are disabled for this local build."
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller
        statusMessage = "Automatic signed updates are enabled."
        controller.updater
            .publisher(for: \.canCheckForUpdates, options: [.initial, .new])
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        guard let updaterController else {
            statusMessage = "Updates are disabled for this local build."
            return
        }

        guard updaterController.updater.canCheckForUpdates else {
            statusMessage = "Updates are not ready to check yet."
            return
        }

        statusMessage = "Checking for signed updates..."
        updaterController.checkForUpdates(nil)
    }

    private static func hasConfiguredPublicEDKey(in bundle: Bundle) -> Bool {
        guard let rawPublicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
            return false
        }

        let publicKey = rawPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return !publicKey.isEmpty && !publicKey.contains("$(")
    }
}
