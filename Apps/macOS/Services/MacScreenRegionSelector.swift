import AppKit
import CoreGraphics
import Foundation

struct MacScreenRegionSelection {
    let captureRect: CGRect
    let displayID: CGDirectDisplayID?
}

enum MacScreenRegionSelectionError: Error, LocalizedError {
    case cancelled
    case noScreenAvailable

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Screen region selection was cancelled."
        case .noScreenAvailable:
            return "No display is available for screen region selection."
        }
    }
}

@MainActor
final class MacScreenRegionSelector: NSObject {
    private static var activeSelector: MacScreenRegionSelector?

    private var continuation: CheckedContinuation<MacScreenRegionSelection, Error>?
    private var windows: [NSWindow] = []

    static func selectRegion() async throws -> MacScreenRegionSelection {
        try await withCheckedThrowingContinuation { continuation in
            let selector = MacScreenRegionSelector(continuation: continuation)
            activeSelector = selector
            selector.begin()
        }
    }

    private init(continuation: CheckedContinuation<MacScreenRegionSelection, Error>) {
        self.continuation = continuation
        super.init()
    }

    private func begin() {
        guard !NSScreen.screens.isEmpty else {
            finish(.failure(MacScreenRegionSelectionError.noScreenAvailable))
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        windows = NSScreen.screens.map { screen in
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            let displayBounds = displayID.map(CGDisplayBounds) ?? screen.frame
            let view = MacScreenRegionSelectionView(
                displayBounds: displayBounds,
                displayID: displayID,
                onComplete: { [weak self] selection in
                    self?.finish(.success(selection))
                },
                onCancel: { [weak self] in
                    self?.finish(.failure(MacScreenRegionSelectionError.cancelled))
                }
            )

            let window = MacScreenRegionSelectionWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.backgroundColor = .clear
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.contentView = view
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.isOpaque = false
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            return window
        }
    }

    private func finish(_ result: Result<MacScreenRegionSelection, Error>) {
        windows.forEach { $0.close() }
        windows.removeAll()

        guard let continuation else { return }
        self.continuation = nil
        MacScreenRegionSelector.activeSelector = nil

        switch result {
        case .success(let selection):
            continuation.resume(returning: selection)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private final class MacScreenRegionSelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class MacScreenRegionSelectionView: NSView {
    private let displayBounds: CGRect
    private let displayID: CGDirectDisplayID?
    private let onComplete: (MacScreenRegionSelection) -> Void
    private let onCancel: () -> Void

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?

    init(
        displayBounds: CGRect,
        displayID: CGDirectDisplayID?,
        onComplete: @escaping (MacScreenRegionSelection) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.displayBounds = displayBounds
        self.displayID = displayID
        self.onComplete = onComplete
        self.onCancel = onCancel
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        dragCurrent = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = event.locationInWindow
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragCurrent = event.locationInWindow
        let rect = selectedRect.integral
        guard rect.width >= 8, rect.height >= 8 else {
            onCancel()
            return
        }

        let captureRect = CGRect(
            x: displayBounds.minX + rect.minX,
            y: displayBounds.minY + displayBounds.height - rect.maxY,
            width: rect.width,
            height: rect.height
        ).integral
        onComplete(MacScreenRegionSelection(captureRect: captureRect, displayID: displayID))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.22).setFill()
        bounds.fill()

        let rect = selectedRect
        guard !rect.isEmpty else {
            drawInstruction()
            return
        }

        NSColor.white.withAlphaComponent(0.14).setFill()
        rect.fill()

        let border = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        border.lineWidth = 2
        NSColor.white.withAlphaComponent(0.95).setStroke()
        border.stroke()
    }

    private var selectedRect: CGRect {
        guard let dragStart, let dragCurrent else {
            return .zero
        }

        return CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragCurrent.x - dragStart.x),
            height: abs(dragCurrent.y - dragStart.y)
        )
    }

    private func drawInstruction() {
        let text = "Drag to capture region. Esc cancels."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let rect = CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        text.draw(in: rect, withAttributes: attributes)
    }
}
