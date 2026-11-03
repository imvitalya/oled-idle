import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: Shortcut
    @Binding var isRecording: Bool
    let localizer: Localizer
    let onCapture: (Shortcut) -> Void
    let onInvalid: () -> Void

    func makeNSView(context: Context) -> RecorderButton { RecorderButton() }
    func updateNSView(_ view: RecorderButton, context: Context) {
        view.shortcut = shortcut
        view.localizer = localizer
        view.onCapture = onCapture
        view.onInvalid = onInvalid
        view.onRecordingChanged = { isRecording = $0 }
        if !isRecording { view.stopRecording() }
        view.refreshTitle()
    }
    static func dismantleNSView(_ view: RecorderButton, coordinator: ()) { view.stopRecording() }
}

final class RecorderButton: NSButton {
    var shortcut = Shortcut.disabled
    var localizer = Localizer(language: .system)
    var onCapture: ((Shortcut) -> Void)?
    var onInvalid: (() -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    private(set) var recording = false
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        target = self
        action = #selector(clicked)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func resignFirstResponder() -> Bool { stopRecording(); return super.resignFirstResponder() }

    func refreshTitle() {
        title = recording ? localizer.text("Press shortcut…") : (shortcut.isDisabled ? localizer.text("Record shortcut…") : shortcut.localizedTitle(using: localizer))
        toolTip = localizer.text("Click, then press your shortcut. Escape cancels.")
        setAccessibilityLabel(localizer.text("Blackout shortcut"))
        setAccessibilityValue(title)
    }
    @objc private func clicked() {
        if recording { stopRecording(); return }
        guard let window = window, window.makeFirstResponder(self) else { return }
        recording = true
        onRecordingChanged?(true)
        refreshTitle()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.recording, event.window === self.window else { return event }
            if event.keyCode == 53 { self.stopRecording(); return nil }
            var flags: UInt32 = 0
            for (eventFlag, carbonFlag) in [(NSEvent.ModifierFlags.command, Shortcut.command),
                (.control, Shortcut.control), (.option, Shortcut.option), (.shift, Shortcut.shift)] {
                if event.modifierFlags.contains(eventFlag) { flags |= carbonFlag }
            }
            let combination = Shortcut(keyCode: UInt32(event.keyCode), modifiers: flags)
            guard combination.isValid else { self.onInvalid?(); return nil }
            self.stopRecording()
            self.onCapture?(combination)
            return nil
        }
        for (name, object) in [(NSWindow.didResignKeyNotification, window as AnyObject?),
                               (NSWindow.willCloseNotification, window as AnyObject?),
                               (NSApplication.didResignActiveNotification, nil)] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                self?.stopRecording()
            })
        }
    }
    func stopRecording() {
        guard recording else { return }
        recording = false
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        refreshTitle()
        onRecordingChanged?(false)
    }
    deinit {
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
