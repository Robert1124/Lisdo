import UIKit

@MainActor
@available(iOSApplicationExtension, unavailable)
enum LisdoBackgroundTaskRunner {
    static func run<T>(
        named name: String,
        operation: () async throws -> T
    ) async throws -> T {
        let token = BackgroundTaskToken(name: name)
        defer { token.end() }
        return try await operation()
    }
}

@MainActor
@available(iOSApplicationExtension, unavailable)
private final class BackgroundTaskToken {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            Task { @MainActor in
                self?.end()
            }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
