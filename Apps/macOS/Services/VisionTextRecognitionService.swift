import AVFoundation
import AppKit
import Carbon
import Combine
import Foundation
import LisdoCore
import ScreenCaptureKit
import Speech
import Vision

public final class VisionTextRecognitionService: TextRecognitionService, @unchecked Sendable {
    public init() {}

    public func recognizeText(from imageData: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(data: imageData, options: [:])
            try handler.perform([request])

            let lines = (request.results ?? [])
                .compactMap { observation -> RecognizedTextLine? in
                    guard let text = observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines),
                          !text.isEmpty
                    else {
                        return nil
                    }
                    return RecognizedTextLine(text: text, boundingBox: observation.boundingBox)
                }
                .sortedForReadingOrder()
                .map(\.text)

            guard !lines.isEmpty else {
                throw TextRecognitionError.noTextFound
            }

            return lines.joined(separator: "\n")
        }.value
    }

    public func recognizeText(from image: NSImage) async throws -> String {
        guard let imageData = image.tiffRepresentation else {
            throw TextRecognitionError.unreadableImage
        }
        return try await recognizeText(from: imageData)
    }
}

private struct RecognizedTextLine {
    var text: String
    var boundingBox: CGRect
}

private extension Array where Element == RecognizedTextLine {
    func sortedForReadingOrder() -> [RecognizedTextLine] {
        sorted { lhs, rhs in
            let rowTolerance = Swift.max(lhs.boundingBox.height, rhs.boundingBox.height) * 0.6
            let yDelta = lhs.boundingBox.midY - rhs.boundingBox.midY
            if abs(yDelta) > rowTolerance {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
    }
}

public enum CLIDraftPromptTransport: String, Codable, Equatable, Sendable {
    case arguments
    case argumentsAndStandardInput
}

public struct MacOnlyCLIProviderSettings: Codable, Equatable, Sendable {
    public var descriptor: CLIDraftProviderDescriptor
    public var executablePath: String?
    public var timeoutSeconds: TimeInterval
    public var environment: [String: String]
    public var promptTransport: CLIDraftPromptTransport

    public init(
        descriptor: CLIDraftProviderDescriptor,
        executablePath: String? = nil,
        timeoutSeconds: TimeInterval? = nil,
        environment: [String: String] = [:],
        promptTransport: CLIDraftPromptTransport = .arguments
    ) {
        var localDescriptor = descriptor
        if let timeoutSeconds {
            localDescriptor.defaultTimeoutSeconds = timeoutSeconds
        }

        self.descriptor = localDescriptor
        self.executablePath = executablePath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.timeoutSeconds = timeoutSeconds ?? descriptor.defaultTimeoutSeconds
        self.environment = environment
        self.promptTransport = promptTransport
    }

    public static func codex(
        executablePath: String? = nil,
        timeoutSeconds: TimeInterval = 120,
        promptTransport: CLIDraftPromptTransport = .arguments
    ) -> MacOnlyCLIProviderSettings {
        MacOnlyCLIProviderSettings(
            descriptor: .codex(defaultTimeoutSeconds: timeoutSeconds),
            executablePath: executablePath,
            timeoutSeconds: timeoutSeconds,
            promptTransport: promptTransport
        )
    }

    public static func claudeCode(
        executablePath: String? = nil,
        timeoutSeconds: TimeInterval = 120,
        promptTransport: CLIDraftPromptTransport = .arguments
    ) -> MacOnlyCLIProviderSettings {
        MacOnlyCLIProviderSettings(
            descriptor: .claudeCode(defaultTimeoutSeconds: timeoutSeconds),
            executablePath: executablePath,
            timeoutSeconds: timeoutSeconds,
            promptTransport: promptTransport
        )
    }

    public static func gemini(
        executablePath: String? = nil,
        timeoutSeconds: TimeInterval = 120,
        promptTransport: CLIDraftPromptTransport = .arguments
    ) -> MacOnlyCLIProviderSettings {
        MacOnlyCLIProviderSettings(
            descriptor: .gemini(defaultTimeoutSeconds: timeoutSeconds),
            executablePath: executablePath,
            timeoutSeconds: timeoutSeconds,
            promptTransport: promptTransport
        )
    }
}

public enum MacOnlyCLIDraftServiceError: Error, Equatable, LocalizedError, Sendable {
    case missingExecutableName(providerName: String)
    case executableNotFound(providerName: String, executableName: String)
    case executablePathNotFound(providerName: String, path: String)
    case executablePathNotExecutable(providerName: String, path: String)
    case launchFailed(providerName: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .missingExecutableName(let providerName):
            return "\(providerName) does not have a CLI executable name configured."
        case .executableNotFound(let providerName, let executableName):
            return "\(providerName) executable '\(executableName)' was not found in PATH."
        case .executablePathNotFound(let providerName, let path):
            return "\(providerName) executable path does not exist: \(path)"
        case .executablePathNotExecutable(let providerName, let path):
            return "\(providerName) executable path is not executable: \(path)"
        case .launchFailed(let providerName, let reason):
            return "\(providerName) could not be launched: \(reason)"
        }
    }
}

public final class CLIDraftCommandRunner: CLIDraftCommandRunning, @unchecked Sendable {
    private let promptTransport: CLIDraftPromptTransport
    private let defaultPATH: String

    public init(
        promptTransport: CLIDraftPromptTransport = .arguments,
        defaultPATH: String = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    ) {
        self.promptTransport = promptTransport
        self.defaultPATH = defaultPATH
    }

    public func run(_ command: CLIDraftCommandInvocation) async throws -> CLIDraftCommandResult {
        let resolvedCommand = try resolveCommand(command)
        let process = Process()
        process.executableURL = resolvedCommand.executableURL
        process.arguments = resolvedCommand.arguments
        process.environment = resolvedCommand.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        let stdoutBuffer = CLIDraftOutputBuffer()
        let stderrBuffer = CLIDraftOutputBuffer()
        let processState = CLIDraftProcessState()

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        if promptTransport == .argumentsAndStandardInput {
            process.standardInput = stdinPipe
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            stdoutBuffer.append(handle.availableData)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            stderrBuffer.append(handle.availableData)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let timeoutWorkItem = DispatchWorkItem {
                processState.markTimedOut()
                if process.isRunning {
                    process.terminate()
                }
            }

            process.terminationHandler = { terminatedProcess in
                timeoutWorkItem.cancel()

                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                stdoutBuffer.append(stdoutPipe.fileHandleForReading.availableData)
                stderrBuffer.append(stderrPipe.fileHandleForReading.availableData)

                continuation.resume(
                    returning: CLIDraftCommandResult(
                        stdout: stdoutBuffer.stringValue(),
                        stderr: stderrBuffer.stringValue(),
                        exitCode: terminatedProcess.terminationStatus,
                        timedOut: processState.wasTimedOut
                    )
                )
            }

            do {
                try process.run()
                if promptTransport == .argumentsAndStandardInput {
                    stdinPipe.fileHandleForWriting.write(Data(command.prompt.utf8))
                    stdinPipe.fileHandleForWriting.closeFile()
                }

                if command.timeoutSeconds > 0 {
                    DispatchQueue.global(qos: .utility).asyncAfter(
                        deadline: .now() + command.timeoutSeconds,
                        execute: timeoutWorkItem
                    )
                }
            } catch {
                timeoutWorkItem.cancel()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(
                    throwing: MacOnlyCLIDraftServiceError.launchFailed(
                        providerName: command.provider.displayName,
                        reason: error.localizedDescription
                    )
                )
            }
        }
    }

    private func resolveCommand(_ command: CLIDraftCommandInvocation) throws -> ResolvedCLICommand {
        let environment = mergedEnvironment(command.environment)

        if let executablePath = command.executablePath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            let expandedPath = (executablePath as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory), !isDirectory.boolValue else {
                throw MacOnlyCLIDraftServiceError.executablePathNotFound(
                    providerName: command.provider.displayName,
                    path: expandedPath
                )
            }
            guard FileManager.default.isExecutableFile(atPath: expandedPath) else {
                throw MacOnlyCLIDraftServiceError.executablePathNotExecutable(
                    providerName: command.provider.displayName,
                    path: expandedPath
                )
            }

            return ResolvedCLICommand(
                executableURL: URL(fileURLWithPath: expandedPath),
                arguments: command.arguments,
                environment: environment
            )
        }

        let executableName = command.executableName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !executableName.isEmpty else {
            throw MacOnlyCLIDraftServiceError.missingExecutableName(providerName: command.provider.displayName)
        }
        guard executableExists(named: executableName, pathValue: environment["PATH"]) else {
            throw MacOnlyCLIDraftServiceError.executableNotFound(
                providerName: command.provider.displayName,
                executableName: executableName
            )
        }

        return ResolvedCLICommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [executableName] + command.arguments,
            environment: environment
        )
    }

    private func mergedEnvironment(_ commandEnvironment: [String: String]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        if environment["PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            environment["PATH"] = defaultPATH
        } else if let existingPATH = environment["PATH"] {
            environment["PATH"] = "\(existingPATH):\(defaultPATH)"
        }
        commandEnvironment.forEach { key, value in
            environment[key] = value
        }
        return environment
    }

    private func executableExists(named executableName: String, pathValue: String?) -> Bool {
        if executableName.contains("/") {
            return FileManager.default.isExecutableFile(atPath: (executableName as NSString).expandingTildeInPath)
        }

        return (pathValue ?? defaultPATH)
            .split(separator: ":")
            .map(String.init)
            .contains { directory in
                let candidate = URL(fileURLWithPath: directory)
                    .appendingPathComponent(executableName)
                    .path
                return FileManager.default.isExecutableFile(atPath: candidate)
            }
    }
}

public final class MacOnlyCLIDraftProvider: TaskDraftProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String
    public let mode: ProviderMode = .macOnlyCLI

    private let settings: MacOnlyCLIProviderSettings
    private let commandBuilder: any CLIDraftCommandBuilding
    private let commandRunner: any CLIDraftCommandRunning

    public convenience init(settings: MacOnlyCLIProviderSettings) {
        self.init(
            settings: settings,
            commandBuilder: CLIDraftCommandStrategy(provider: settings.descriptor),
            commandRunner: CLIDraftCommandRunner(promptTransport: settings.promptTransport)
        )
    }

    public init(
        settings: MacOnlyCLIProviderSettings,
        commandBuilder: any CLIDraftCommandBuilding,
        commandRunner: any CLIDraftCommandRunning
    ) {
        self.settings = settings
        self.commandBuilder = commandBuilder
        self.commandRunner = commandRunner
        self.id = settings.descriptor.id
        self.displayName = settings.descriptor.displayName
    }

    public func generateDraft(
        input: TaskDraftInput,
        categories: [LisdoCore.Category],
        options: TaskDraftProviderOptions
    ) async throws -> ProcessingDraft {
        let materializedAttachments = try CLIMediaAttachmentMaterializer.materialize(input: input)
        defer { materializedAttachments.cleanup() }

        var cliInput = input
        if !materializedAttachments.promptContext.isEmpty {
            cliInput.sourceText = [
                input.sourceText.trimmingCharacters(in: .whitespacesAndNewlines),
                materializedAttachments.promptContext
            ]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        }

        var command = commandBuilder.makeCommand(
            input: cliInput,
            categories: categories,
            options: options
        )
        command.executablePath = settings.executablePath
        command.timeoutSeconds = settings.timeoutSeconds
        settings.environment.forEach { key, value in
            command.environment[key] = value
        }
        materializedAttachments.environment.forEach { key, value in
            command.environment[key] = value
        }

        let result = try await commandRunner.run(command)
        return try CLIStrictDraftParser.parseResult(
            result,
            captureItemId: input.captureItemId,
            provider: settings.descriptor
        )
    }
}

private struct CLIMediaAttachmentMaterializer {
    struct MaterializedAttachments {
        var promptContext: String
        var environment: [String: String]
        var directoryURL: URL?

        func cleanup() {
            guard let directoryURL else { return }
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    private struct FileDescriptor {
        var kind: String
        var filename: String
        var format: String
        var data: Data
    }

    static func materialize(input: TaskDraftInput) throws -> MaterializedAttachments {
        let descriptors = fileDescriptors(input: input)
        guard !descriptors.isEmpty else {
            return MaterializedAttachments(promptContext: "", environment: [:], directoryURL: nil)
        }

        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LisdoCLI-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            var lines: [String] = []
            var imagePaths: [String] = []
            var audioPaths: [String] = []
            var usedFilenames = Set<String>()

            for descriptor in descriptors {
                let filename = uniqueFilename(
                    preferred: descriptor.filename,
                    fallback: "\(descriptor.kind).dat",
                    usedFilenames: &usedFilenames
                )
                let fileURL = directoryURL.appendingPathComponent(filename, isDirectory: false)
                try descriptor.data.write(to: fileURL, options: [.atomic])
                lines.append("- \(descriptor.kind): \(fileURL.path) (\(descriptor.format), \(descriptor.data.count) bytes)")
                if descriptor.kind == "image" {
                    imagePaths.append(fileURL.path)
                } else if descriptor.kind == "audio" {
                    audioPaths.append(fileURL.path)
                }
            }

            var environment: [String: String] = [:]
            if !imagePaths.isEmpty {
                environment["LISDO_IMAGE_ATTACHMENT_PATHS"] = imagePaths.joined(separator: ":")
            }
            if !audioPaths.isEmpty {
                environment["LISDO_AUDIO_ATTACHMENT_PATHS"] = audioPaths.joined(separator: ":")
            }

            let promptContext = """
            Direct media files were materialized on this Mac for CLI processing. Inspect these local paths if the selected CLI can read image or audio files:
            \(lines.joined(separator: "\n"))
            These files are temporary and will be deleted after this processing attempt. Return only Lisdo's strict draft JSON for user review.
            """

            return MaterializedAttachments(
                promptContext: promptContext,
                environment: environment,
                directoryURL: directoryURL
            )
        } catch {
            try? FileManager.default.removeItem(at: directoryURL)
            throw error
        }
    }

    private static func fileDescriptors(input: TaskDraftInput) -> [FileDescriptor] {
        var descriptors: [FileDescriptor] = []
        for imageAttachment in input.allImageAttachments {
            descriptors.append(
                FileDescriptor(
                    kind: "image",
                    filename: sanitizedFilename(
                        imageAttachment.filename,
                        fallback: "image.\(imageFileExtension(for: imageAttachment.mimeType))"
                    ),
                    format: imageAttachment.mimeType,
                    data: imageAttachment.data
                )
            )
        }
        for audioAttachment in input.allAudioAttachments {
            descriptors.append(
                FileDescriptor(
                    kind: "audio",
                    filename: sanitizedFilename(
                        audioAttachment.filename,
                        fallback: "audio.\(audioFileExtension(for: audioAttachment.format))"
                    ),
                    format: audioAttachment.format,
                    data: audioAttachment.data
                )
            )
        }
        return descriptors
    }

    private static func sanitizedFilename(_ filename: String?, fallback: String) -> String {
        guard let lastPathComponent = filename?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            .map({ URL(fileURLWithPath: $0).lastPathComponent }),
            !lastPathComponent.isEmpty,
            lastPathComponent != "."
        else {
            return fallback
        }

        return lastPathComponent
    }

    private static func uniqueFilename(
        preferred: String,
        fallback: String,
        usedFilenames: inout Set<String>
    ) -> String {
        let base = preferred.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? fallback
        if usedFilenames.insert(base).inserted {
            return base
        }

        let url = URL(fileURLWithPath: base)
        let name = url.deletingPathExtension().lastPathComponent.nilIfEmpty ?? "attachment"
        let pathExtension = url.pathExtension
        var index = 2
        while true {
            let candidate = pathExtension.isEmpty ? "\(name)-\(index)" : "\(name)-\(index).\(pathExtension)"
            if usedFilenames.insert(candidate).inserted {
                return candidate
            }
            index += 1
        }
    }

    private static func imageFileExtension(for mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "image/jpeg", "image/jpg":
            return "jpg"
        case "image/heic":
            return "heic"
        case "image/tiff":
            return "tiff"
        case "image/gif":
            return "gif"
        default:
            return "png"
        }
    }

    private static func audioFileExtension(for format: String) -> String {
        let lowercased = format.lowercased()
        if lowercased.contains("wav") {
            return "wav"
        }
        if lowercased.contains("mp3") || lowercased.contains("mpeg") {
            return "mp3"
        }
        if lowercased.contains("caf") {
            return "caf"
        }
        return "m4a"
    }
}

public enum MacScreenCaptureAuthorizationState: Equatable, Sendable {
    case authorized
    case notDeterminedOrDenied
}

public enum MacScreenCaptureError: Error, Equatable, LocalizedError, Sendable {
    case permissionDenied
    case displayNotFound(CGDirectDisplayID)
    case captureFailed
    case imageEncodingFailed

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen recording permission is required before Lisdo can capture screen regions."
        case .displayNotFound(let displayID):
            return "Display \(displayID) could not be found for screen capture."
        case .captureFailed:
            return "The screen region could not be captured."
        case .imageEncodingFailed:
            return "The captured screen image could not be encoded as PNG data."
        }
    }
}

public final class MacScreenCaptureService: @unchecked Sendable {
    public init() {}

    public func authorizationState() -> MacScreenCaptureAuthorizationState {
        CGPreflightScreenCaptureAccess() ? .authorized : .notDeterminedOrDenied
    }

    @discardableResult
    public func requestScreenRecordingAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public func captureMainDisplayPNGData() async throws -> Data {
        try await captureDisplayPNGData(displayID: CGMainDisplayID())
    }

    public func captureDisplayPNGData(displayID: CGDirectDisplayID) async throws -> Data {
        let bounds = CGDisplayBounds(displayID)
        guard bounds != .null, !bounds.isEmpty else {
            throw MacScreenCaptureError.displayNotFound(displayID)
        }
        return try await capturePNGData(rect: bounds, displayID: displayID)
    }

    public func capturePNGData(rect: CGRect, displayID: CGDirectDisplayID? = nil) async throws -> Data {
        guard authorizationState() == .authorized else {
            throw MacScreenCaptureError.permissionDenied
        }

        let normalizedRect = rect.standardized.integral
        guard !normalizedRect.isEmpty else {
            throw MacScreenCaptureError.captureFailed
        }

        if let image = try await captureWithScreenCaptureKit(rect: normalizedRect, displayID: displayID) {
            return try pngData(from: image)
        }
        throw MacScreenCaptureError.captureFailed
    }

    private func captureWithScreenCaptureKit(
        rect: CGRect,
        displayID: CGDirectDisplayID?
    ) async throws -> CGImage? {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        let display = try matchingDisplay(
            for: rect,
            preferredDisplayID: displayID,
            displays: content.displays
        )
        let displayFrame = display.frame
        let sourceRect = rect.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = max(Int(sourceRect.width), 1)
        configuration.height = max(Int(sourceRect.height), 1)
        configuration.showsCursor = false

        let filter = SCContentFilter(display: display, excludingWindows: [])
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    private func matchingDisplay(
        for rect: CGRect,
        preferredDisplayID: CGDirectDisplayID?,
        displays: [SCDisplay]
    ) throws -> SCDisplay {
        if let preferredDisplayID,
           let display = displays.first(where: { $0.displayID == preferredDisplayID }) {
            return display
        }
        if let display = displays.first(where: { $0.frame.intersects(rect) }) {
            return display
        }
        let mainDisplayID = CGMainDisplayID()
        if let display = displays.first(where: { $0.displayID == mainDisplayID }) {
            return display
        }
        throw MacScreenCaptureError.displayNotFound(preferredDisplayID ?? mainDisplayID)
    }

    private func pngData(from image: CGImage) throws -> Data {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw MacScreenCaptureError.imageEncodingFailed
        }
        return data
    }
}

public struct MacGlobalHotKey: Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum MacGlobalHotKeyError: Error, Equatable, LocalizedError, Sendable {
    case eventHandlerInstallFailed(OSStatus)
    case registrationFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .eventHandlerInstallFailed(let status):
            return "Global hotkey event handler could not be installed. Carbon status: \(status)."
        case .registrationFailed(let status):
            return "Global hotkey could not be registered. Carbon status: \(status)."
        }
    }
}

public final class MacGlobalHotKeyRegistrar: @unchecked Sendable {
    private let lock = NSLock()
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var callback: (@Sendable () -> Void)?
    private var hotKeyID: EventHotKeyID

    public init(identifier: UInt32 = 1) {
        self.hotKeyID = EventHotKeyID(
            signature: MacGlobalHotKeyRegistrar.eventSignature,
            id: identifier
        )
    }

    deinit {
        unregister()
    }

    public func register(
        hotKey: MacGlobalHotKey,
        callback: @escaping @Sendable () -> Void
    ) throws {
        unregister()
        try installEventHandlerIfNeeded()

        var newHotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newHotKeyRef
        )

        guard status == noErr, let newHotKeyRef else {
            throw MacGlobalHotKeyError.registrationFailed(status)
        }

        lock.lock()
        hotKeyRef = newHotKeyRef
        self.callback = callback
        lock.unlock()
    }

    public func unregister() {
        lock.lock()
        let registeredHotKeyRef = hotKeyRef
        hotKeyRef = nil
        callback = nil
        lock.unlock()

        if let registeredHotKeyRef {
            UnregisterEventHotKey(registeredHotKeyRef)
        }
    }

    private func installEventHandlerIfNeeded() throws {
        lock.lock()
        let isInstalled = eventHandlerRef != nil
        lock.unlock()

        guard !isInstalled else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var newHandlerRef: EventHandlerRef?
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            MacGlobalHotKeyRegistrar.eventHandler,
            1,
            &eventType,
            userData,
            &newHandlerRef
        )

        guard status == noErr, let newHandlerRef else {
            throw MacGlobalHotKeyError.eventHandlerInstallFailed(status)
        }

        lock.lock()
        eventHandlerRef = newHandlerRef
        lock.unlock()
    }

    private func handleHotKeyEvent(id: EventHotKeyID) {
        guard id.signature == hotKeyID.signature, id.id == hotKeyID.id else {
            return
        }

        lock.lock()
        let callback = self.callback
        lock.unlock()

        DispatchQueue.main.async {
            callback?()
        }
    }

    private static let eventSignature: OSType = {
        Array("LSDO".utf8).reduce(0) { partial, scalar in
            (partial << 8) + OSType(scalar)
        }
    }()

    private static let eventHandler: EventHandlerUPP = { _, eventRef, userData in
        guard let eventRef, let userData else {
            return OSStatus(eventNotHandledErr)
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else {
            return status
        }

        let registrar = Unmanaged<MacGlobalHotKeyRegistrar>
            .fromOpaque(userData)
            .takeUnretainedValue()
        registrar.handleHotKeyEvent(id: hotKeyID)
        return noErr
    }
}

public enum MacSpeechAuthorizationState: Equatable, Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined

    init(_ status: SFSpeechRecognizerAuthorizationStatus) {
        switch status {
        case .authorized:
            self = .authorized
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        case .notDetermined:
            self = .notDetermined
        @unknown default:
            self = .restricted
        }
    }
}

public enum MacMicrophoneAuthorizationState: Equatable, Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized:
            self = .authorized
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        case .notDetermined:
            self = .notDetermined
        @unknown default:
            self = .restricted
        }
    }
}

public enum MacVoiceRecordingError: Error, Equatable, LocalizedError, Sendable {
    case microphoneNotAuthorized(MacMicrophoneAuthorizationState)
    case recorderCouldNotStart
    case noActiveRecording

    public var errorDescription: String? {
        switch self {
        case .microphoneNotAuthorized(let state):
            return "Microphone access is not authorized. Current state: \(state)."
        case .recorderCouldNotStart:
            return "Lisdo could not start recording. Check microphone access and try again."
        case .noActiveRecording:
            return "There is no active voice recording to stop."
        }
    }
}

@MainActor
public final class MacVoiceRecordingService: NSObject, ObservableObject {
    @Published public private(set) var isRecording = false
    @Published public private(set) var currentRecordingURL: URL?

    private var recorder: AVAudioRecorder?

    public override init() {
        super.init()
    }

    public func microphoneAuthorizationState() -> MacMicrophoneAuthorizationState {
        MacMicrophoneAuthorizationState(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    public func startRecording() async throws {
        guard !isRecording else { return }

        try await requestMicrophoneAccess()
        discardRecording()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lisdo-voice-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true

        guard recorder.record() else {
            try? FileManager.default.removeItem(at: url)
            throw MacVoiceRecordingError.recorderCouldNotStart
        }

        self.recorder = recorder
        currentRecordingURL = url
        isRecording = true
    }

    public func stopRecording() throws -> URL {
        guard let recorder, isRecording else {
            throw MacVoiceRecordingError.noActiveRecording
        }

        let url = recorder.url
        recorder.stop()
        self.recorder = nil
        currentRecordingURL = url
        isRecording = false
        return url
    }

    public func discardRecording() {
        recorder?.stop()
        recorder = nil
        isRecording = false

        if let currentRecordingURL {
            try? FileManager.default.removeItem(at: currentRecordingURL)
        }
        currentRecordingURL = nil
    }

    public func discardRecording(at url: URL) {
        if currentRecordingURL == url {
            currentRecordingURL = nil
        }
        try? FileManager.default.removeItem(at: url)
    }

    private func requestMicrophoneAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .denied:
            throw MacVoiceRecordingError.microphoneNotAuthorized(.denied)
        case .restricted:
            throw MacVoiceRecordingError.microphoneNotAuthorized(.restricted)
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else {
                throw MacVoiceRecordingError.microphoneNotAuthorized(.denied)
            }
        @unknown default:
            throw MacVoiceRecordingError.microphoneNotAuthorized(.restricted)
        }
    }
}

extension MacVoiceRecordingService: AVAudioRecorderDelegate {}

public struct MacSpeechTranscriptionResult: Equatable, Sendable {
    public var transcript: String
    public var isFinal: Bool
    public var languageCode: String?
    public var confidence: Double

    public init(
        transcript: String,
        isFinal: Bool,
        languageCode: String? = nil,
        confidence: Double = 0
    ) {
        self.transcript = transcript
        self.isFinal = isFinal
        self.languageCode = languageCode
        self.confidence = confidence
    }
}

public enum MacSpeechTranscriptionError: Error, Equatable, LocalizedError, Sendable {
    case speechRecognitionNotAuthorized(MacSpeechAuthorizationState)
    case recognizerUnavailable(localeIdentifier: String)
    case transcriptionFailed(String)
    case emptyTranscript

    public var errorDescription: String? {
        switch self {
        case .speechRecognitionNotAuthorized(let state):
            return "Speech recognition is not authorized. Current state: \(state)."
        case .recognizerUnavailable(let localeIdentifier):
            return "Speech recognition is unavailable for \(localeIdentifier)."
        case .transcriptionFailed(let reason):
            return "Speech transcription failed: \(reason)"
        case .emptyTranscript:
            return "Speech transcription completed without recognized text."
        }
    }
}

public final class MacSpeechTranscriptionService: @unchecked Sendable {
    public init() {}

    public func authorizationState() -> MacSpeechAuthorizationState {
        MacSpeechAuthorizationState(SFSpeechRecognizer.authorizationStatus())
    }

    public func requestSpeechRecognitionAuthorization() async -> MacSpeechAuthorizationState {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: MacSpeechAuthorizationState(status))
            }
        }
    }

    public func transcribeAudioFile(
        at audioURL: URL,
        locale: Locale = .current,
        contextualStrings: [String] = []
    ) async throws -> MacSpeechTranscriptionResult {
        let state = authorizationState()
        guard state == .authorized else {
            throw MacSpeechTranscriptionError.speechRecognitionNotAuthorized(state)
        }

        var candidates: [LisdoSpeechTranscriptCandidate] = []
        var lastError: Error?
        for candidateLocale in fallbackLocales(primary: locale) {
            do {
                let result = try await transcribeAudioFileOnce(
                    at: audioURL,
                    locale: candidateLocale,
                    contextualStrings: contextualStrings
                )
                candidates.append(
                    LisdoSpeechTranscriptCandidate(
                        text: result.transcript,
                        languageCode: result.languageCode ?? candidateLocale.identifier,
                        confidence: result.confidence
                    )
                )
            } catch let error as MacSpeechTranscriptionError {
                lastError = error
                if case .speechRecognitionNotAuthorized = error {
                    throw error
                }
            } catch {
                lastError = error
            }
        }

        if let bestCandidate = LisdoSpeechLocalePolicy.bestCandidate(candidates) {
            return MacSpeechTranscriptionResult(
                transcript: bestCandidate.text,
                isFinal: true,
                languageCode: bestCandidate.languageCode,
                confidence: bestCandidate.confidence
            )
        }

        throw lastError ?? MacSpeechTranscriptionError.emptyTranscript
    }

    private func transcribeAudioFileOnce(
        at audioURL: URL,
        locale: Locale,
        contextualStrings: [String]
    ) async throws -> MacSpeechTranscriptionResult {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw MacSpeechTranscriptionError.recognizerUnavailable(localeIdentifier: locale.identifier)
        }
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.contextualStrings = contextualStrings
        request.taskHint = .dictation

        return try await withCheckedThrowingContinuation { continuation in
            let completionState = MacSpeechContinuationState()
            var recognitionTask: SFSpeechRecognitionTask?

            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    if completionState.complete() {
                        recognitionTask?.cancel()
                        continuation.resume(
                            throwing: MacSpeechTranscriptionError.transcriptionFailed(error.localizedDescription)
                        )
                    }
                    return
                }

                guard let result else {
                    return
                }

                let transcript = result.bestTranscription.formattedString
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard result.isFinal else {
                    return
                }

                if completionState.complete() {
                    if transcript.isEmpty {
                        continuation.resume(throwing: MacSpeechTranscriptionError.emptyTranscript)
                    } else {
                        continuation.resume(
                            returning: MacSpeechTranscriptionResult(
                                transcript: transcript,
                                isFinal: result.isFinal,
                                languageCode: locale.identifier,
                                confidence: self.averageConfidence(for: result.bestTranscription)
                            )
                        )
                    }
                }
            }
        }
    }

    private func fallbackLocales(primary: Locale) -> [Locale] {
        LisdoSpeechLocalePolicy.candidateLocaleIdentifiers(primaryIdentifier: primary.identifier)
            .map(Locale.init(identifier:))
    }

    private func averageConfidence(for transcription: SFTranscription) -> Double {
        let confidenceValues = transcription.segments
            .map(\.confidence)
            .filter { $0 > 0 }

        guard !confidenceValues.isEmpty else {
            return 0
        }

        let total = confidenceValues.reduce(0, +)
        return Double(total / Float(confidenceValues.count))
    }
}

@MainActor
public final class MacLiveVoiceTranscriptionService: NSObject, ObservableObject {
    @Published public private(set) var isRecording = false
    @Published public private(set) var currentRecordingURL: URL?

    private let speechService = MacSpeechTranscriptionService()
    private var audioEngine: AVAudioEngine?

    public override init() {
        super.init()
    }

    public func microphoneAuthorizationState() -> MacMicrophoneAuthorizationState {
        MacMicrophoneAuthorizationState(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    public func startRecording(
        onTranscript: @escaping @MainActor @Sendable (MacSpeechTranscriptionResult) -> Void
    ) async throws {
        guard !isRecording else { return }
        _ = onTranscript

        try await requestMicrophoneAccess()
        try await requestSpeechRecognitionAccess()
        discardRecording()

        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let recordingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lisdo-live-voice-\(UUID().uuidString)")
            .appendingPathExtension("caf")
        let audioFile = try AVAudioFile(forWriting: recordingURL, settings: inputFormat.settings)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            try? audioFile.write(from: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        self.audioEngine = audioEngine
        currentRecordingURL = recordingURL
        isRecording = true
    }

    public func stopAndTranscribe() async throws -> MacSpeechTranscriptionResult {
        guard let recordingURL = currentRecordingURL else {
            throw MacVoiceRecordingError.noActiveRecording
        }

        stopAudioEngine()

        do {
            let result = try await speechService.transcribeAudioFile(at: recordingURL)
            try? FileManager.default.removeItem(at: recordingURL)
            currentRecordingURL = nil
            return result
        } catch {
            try? FileManager.default.removeItem(at: recordingURL)
            currentRecordingURL = nil
            throw error
        }
    }

    public func discardRecording() {
        stopAudioEngine()
        if let currentRecordingURL {
            try? FileManager.default.removeItem(at: currentRecordingURL)
        }
        currentRecordingURL = nil
    }

    private func stopAudioEngine() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false
    }

    private func requestMicrophoneAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .denied:
            throw MacVoiceRecordingError.microphoneNotAuthorized(.denied)
        case .restricted:
            throw MacVoiceRecordingError.microphoneNotAuthorized(.restricted)
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else {
                throw MacVoiceRecordingError.microphoneNotAuthorized(.denied)
            }
        @unknown default:
            throw MacVoiceRecordingError.microphoneNotAuthorized(.restricted)
        }
    }

    private func requestSpeechRecognitionAccess() async throws {
        switch speechService.authorizationState() {
        case .authorized:
            return
        case .notDetermined:
            let requestedState = await speechService.requestSpeechRecognitionAuthorization()
            guard requestedState == .authorized else {
                throw MacSpeechTranscriptionError.speechRecognitionNotAuthorized(requestedState)
            }
        case .denied, .restricted:
            throw MacSpeechTranscriptionError.speechRecognitionNotAuthorized(speechService.authorizationState())
        }
    }

    private static func averageConfidence(for transcription: SFTranscription) -> Double {
        let confidenceValues = transcription.segments
            .map(\.confidence)
            .filter { $0 > 0 }

        guard !confidenceValues.isEmpty else {
            return 0
        }

        let total = confidenceValues.reduce(0, +)
        return Double(total / Float(confidenceValues.count))
    }
}

private struct ResolvedCLICommand {
    var executableURL: URL
    var arguments: [String]
    var environment: [String: String]
}

private final class CLIDraftOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else {
            return
        }

        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func stringValue() -> String {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return String(data: snapshot, encoding: .utf8) ?? String(decoding: snapshot, as: UTF8.self)
    }
}

private final class CLIDraftProcessState: @unchecked Sendable {
    private let lock = NSLock()
    private var timedOut = false

    var wasTimedOut: Bool {
        lock.lock()
        let value = timedOut
        lock.unlock()
        return value
    }

    func markTimedOut() {
        lock.lock()
        timedOut = true
        lock.unlock()
    }
}

private final class MacSpeechContinuationState: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func complete() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !completed else {
            return false
        }
        completed = true
        return true
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
