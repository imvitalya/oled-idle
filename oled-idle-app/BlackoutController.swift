import AppKit

private final class BlackWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class BlackView: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1).setFill()
        dirtyRect.fill()
    }
}

final class BlackoutController {
    private(set) var windows: [NSWindow] = []
    private var monitor: Any?
    private var cursorHidden = false
    private var previousApp: NSRunningApplication?
    private var previousPresentation: NSApplication.PresentationOptions = []
    private var startedAt = 0.0
    private var wakeOnMouseMove = false
    var onDismiss: (() -> Void)?
    var isActive: Bool { !windows.isEmpty }

    @discardableResult
    func show(screens: [NSScreen], wakeOnMouseMove: Bool) -> Bool {
        guard !isActive, !screens.isEmpty else { return false }
        self.wakeOnMouseMove = wakeOnMouseMove
        startedAt = ProcessInfo.processInfo.systemUptime
        previousApp = NSWorkspace.shared.frontmostApplication
        previousPresentation = NSApp.presentationOptions
        createWindows(screens)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown,
            .otherMouseDown, .leftMouseUp, .rightMouseUp, .otherMouseUp, .mouseMoved, .leftMouseDragged,
            .rightMouseDragged, .otherMouseDragged, .scrollWheel]) { [weak self] event in
            guard let self = self, self.isActive else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.dismiss() }
                return nil
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - self.startedAt
            let click = [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type)
            let move = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(event.type)
            if elapsed >= 0.5 && (click || (move && self.wakeOnMouseMove)) { self.dismiss() }
            return nil
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        hideCursor()
        return true
    }

    func update(screens: [NSScreen]) {
        guard isActive else { return }
        guard !screens.isEmpty else { dismiss(); return }
        closeWindows()
        createWindows(screens)
        if NSApp.isActive { windows.first?.makeKeyAndOrderFront(nil) }
    }

    private func createWindows(_ screens: [NSScreen]) {
        windows = screens.map { screen in
            let window = BlackWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.setFrame(screen.frame, display: false)
            window.backgroundColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
            window.isOpaque = true
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.hidesOnDeactivate = false
            window.acceptsMouseMovedEvents = true
            window.animationBehavior = .none
            window.contentView = BlackView(frame: NSRect(origin: .zero, size: screen.frame.size))
            window.orderFrontRegardless()
            return window
        }
    }

    func applicationResignedActive() {
        // Never leave the user looking at an overlay while keyboard input goes to another app.
        if isActive { dismiss(restoreFocus: false) }
    }

    func dismiss(restoreFocus: Bool = true) {
        guard isActive else { return }
        let ownedFocus = NSApp.isActive
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        closeWindows()
        if cursorHidden { NSCursor.unhide(); cursorHidden = false }
        NSApp.presentationOptions = previousPresentation
        if restoreFocus && ownedFocus, let previousApp = previousApp,
           previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier, !previousApp.isTerminated {
            previousApp.activate(options: [])
        }
        previousApp = nil
        onDismiss?()
    }
    private func closeWindows() {
        for window in windows { window.orderOut(nil); window.close() }
        windows.removeAll()
    }
    private func hideCursor() {
        if !cursorHidden { NSCursor.hide(); cursorHidden = true }
    }
}
