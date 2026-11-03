import AppKit
import SwiftUI
import ServiceManagement

final class AppModel: ObservableObject {
    private let defaults: UserDefaults
    @Published var preferences: Preferences {
        didSet {
            let normalized = preferences.normalized()
            // @Published re-enters didSet on assignment, even when the value is equal.
            if normalized != preferences {
                preferences = normalized
                return
            }
            guard preferences != oldValue else { return }
            if preferences.language != oldValue.language { loginIssue = nil }
            preferences.save(to: defaults)
            onPreferencesChange?()
        }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = Preferences.load(from: defaults)
    }
    @Published var enabled = false
    @Published private(set) var status = ""
    @Published private(set) var issue: String?
    @Published var shortcutIssue: String?
    @Published var displays: [DisplayInfo] = []
    @Published var loginEnabled = false
    @Published var loginNeedsApproval = false
    @Published var loginIssue: String?
    var localizer: Localizer { Localizer(language: preferences.language) }
    @Published var isRecordingShortcut = false {
        didSet {
            guard isRecordingShortcut != oldValue else { return }
            invalidShortcut = false
            onShortcutRecordingChange?()
        }
    }
    @Published var invalidShortcut = false
    var onShortcutRecordingChange: (() -> Void)?
    var onPreferencesChange: (() -> Void)?
    var onToggle: (() -> Void)?
    var onBlackout: (() -> Void)?
    var onRetry: (() -> Void)?

    func showStatus(_ value: String) {
        if status != value { status = value }
    }
    func setIssue(_ value: String?) {
        if issue != value { issue = value }
    }

    func refreshLogin() {
        let status = SMAppService.mainApp.status
        let enabled = status == .enabled || status == .requiresApproval
        let needsApproval = status == .requiresApproval
        if loginEnabled != enabled { loginEnabled = enabled }
        if loginNeedsApproval != needsApproval { loginNeedsApproval = needsApproval }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginIssue = nil
        } catch { loginIssue = localizer.text("Could not update launch at login. Check macOS Login Items.") }
        refreshLogin()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var l: Localizer { model.localizer }
    private var policy = IdlePolicy()
    private let power = PowerManager()
    private let blackout = BlackoutController()
    private let probe = CaffeineProbe()
    private let hotkey = GlobalHotKey()
    private let logger = AppLog()
    private var item: NSStatusItem!
    private var lastIconState: (Bool, String, String?)?
    private var timer: Timer?
    private var settingsWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var caffeineState: CaffeineState?
    private var caffeineDenied = false
    private var suspended = false
    private var terminating = false
    private var lastProbeAt = -Double.infinity
    private let dryRun = CommandLine.arguments.contains("--dry-run")

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        policy.toggle()
        model.enabled = CommandLine.arguments.contains("--enabled") || model.preferences.startEnabled
        if model.enabled { policy.toggle() }
        model.onPreferencesChange = { [weak self] in self?.preferencesChanged() }
        model.onShortcutRecordingChange = { [weak self] in self?.recordingChanged() }
        model.onToggle = { [weak self] in self?.toggle() }
        model.onBlackout = { [weak self] in self?.blackoutNow() }
        model.onRetry = { [weak self] in self?.preferencesChanged() }
        hotkey.onPress = { [weak self] in
            guard let self = self, !self.model.isRecordingShortcut else { return }
            if self.blackout.isActive { self.blackout.dismiss() }
            else { self.blackoutNow() }
        }
        blackout.onDismiss = { [weak self] in
            guard let self = self else { return }
            self.policy.restart()
            self.probe.cancel()
            self.updatePower()
            self.refreshStatus()
            self.logger.write("Blackout dismissed; idle interval restarted.")
        }
        observeSystem()
        preferencesChanged()
        let next = Timer(timeInterval: 2, target: self, selector: #selector(sample), userInfo: nil, repeats: true)
        RunLoop.main.add(next, forMode: .common)
        timer = next
        let firstLaunch = !UserDefaults.standard.bool(forKey: "shownStandaloneSettings")
        if firstLaunch || CommandLine.arguments.contains("--settings") {
            UserDefaults.standard.set(true, forKey: "shownStandaloneSettings")
            showSettings()
        }
        logger.write("Started v2. Enabled: \(model.enabled); mode: \(model.preferences.mode.rawValue); dry-run: \(dryRun).")
    }

    private func observeSystem() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.model.displays = DisplayInfo.connected()
            self.blackout.update(screens: self.selectedScreens())
            self.policy.restart()
            self.refreshStatus()
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.suspend()
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self = self else { return }
                self.suspended = false
                self.policy.restart()
                self.updatePower()
                self.refreshStatus()
            })
        }
    }

    private func suspend() {
        suspended = true
        probe.cancel()
        blackout.dismiss(restoreFocus: false)
        policy.restart()
        updatePower()
    }

    private func preferencesChanged() {
        model.isRecordingShortcut = false
        blackout.dismiss()
        probe.cancel()
        policy.threshold = Double(model.preferences.idleMinutes * 60)
        policy.restart()
        model.setIssue(nil)
        caffeineDenied = false
        caffeineState = nil
        lastProbeAt = -.infinity
        model.displays = DisplayInfo.connected()
        model.shortcutIssue = hotkey.register(model.preferences.shortcut, localizer: l)
        model.refreshLogin()
        updatePower()
        refreshStatus()
    }

    private func recordingChanged() {
        guard !terminating else { return }
        policy.restart()
        probe.cancel()
        model.shortcutIssue = hotkey.register(model.isRecordingShortcut ? .disabled : model.preferences.shortcut, localizer: l)
    }

    @objc private func toggle() {
        policy.toggle()
        model.enabled = policy.isEnabled
        preferencesChanged()
        logger.write(model.enabled ? "Enabled." : "Paused.")
    }

    private func updatePower() {
        let needed = !terminating && !suspended && (blackout.isActive || (model.enabled && model.preferences.mode == .standalone))
        do { try power.setActive(needed) }
        catch { logger.write(error.localizedDescription); setError(l.text("macOS could not keep the Mac awake. Try enabling protection again.")) }
    }

    private func selectedScreens() -> [NSScreen] {
        let selected = Set(model.preferences.selectedDisplays(from: model.displays.map(\.id)))
        return model.displays.filter { selected.contains($0.id) }.map(\.screen)
    }

    @objc private func sample() {
        guard policy.isEnabled, !suspended, !blackout.isActive, !terminating, !model.isRecordingShortcut else { return }
        if model.preferences.mode == .standalone {
            updatePower()
            guard power.isActive else { return }
            applySample(active: true, generation: policy.generation)
        } else {
            guard !caffeineDenied, !probe.isRunning, ProcessInfo.processInfo.systemUptime - lastProbeAt >= 5 else { return }
            lastProbeAt = ProcessInfo.processInfo.systemUptime
            let generation = policy.generation
            probe.read { [weak self] state in
                guard let self = self, self.policy.acceptsSample(generation: generation), !self.suspended else { return }
                guard let state = state else {
                    self.caffeineDenied = true
                    self.setError(self.l.text("Caffeine did not respond. Check Automation permission, then click Retry check."))
                    return
                }
                self.caffeineState = state
                self.applySample(active: state == .active, generation: generation)
            }
        }
    }

    private func applySample(active: Bool, generation: Int) {
        guard policy.acceptsSample(generation: generation) else { return }
        guard let idle = inputIdleSeconds() else { setError(l.text("Could not read the idle time.")); return }
        let targetsAvailable = !selectedScreens().isEmpty
        if targetsAvailable { model.setIssue(nil) }
        else { setError(l.text("Selected displays are disconnected. Waiting for a display or a new selection.")) }
        refreshStatus()
        let externalBlackout = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.example.oledblackout").isEmpty
        guard policy.shouldLaunch(caffeineActive: active, idleSeconds: idle, blackoutRunning: externalBlackout,
                                  targetsAvailable: targetsAvailable) else { return }
        if dryRun { logger.write("DRY RUN: would black out; idle \(Int(idle)) seconds."); return }
        if !beginBlackout() { policy.launchFailed(generation: generation) }
    }

    @objc private func blackoutNow() {
        guard !suspended, !terminating, !model.isRecordingShortcut else { return }
        if blackout.isActive { blackout.dismiss(); return }
        policy.restart()
        probe.cancel()
        if dryRun { logger.write("DRY RUN: manual blackout requested."); return }
        _ = beginBlackout(manual: true)
    }

    @discardableResult
    private func beginBlackout(manual: Bool = false) -> Bool {
        let screens = selectedScreens()
        guard !screens.isEmpty else {
            setError(l.text("Select at least one connected display in Settings."))
            if manual { showSettings() }
            return false
        }
        do { try power.setActive(true) }
        catch { logger.write(error.localizedDescription); setError(l.text("macOS could not keep the Mac awake. Try enabling protection again.")); return false }
        let started = blackout.show(screens: screens, wakeOnMouseMove: model.preferences.wakeOnMouseMove)
        if started { logger.write("Blackout on \(screens.count) display(s).") }
        else { updatePower() }
        return started
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() }
        else { toggle() }
    }
    private func refreshStatus() {
        let status: String
        if !model.enabled { status = l.text("Paused") }
        else if model.preferences.mode == .standalone { status = l.text("Active · blackout after %ld min of inactivity", model.preferences.idleMinutes) }
        else {
            switch caffeineState {
            case .active: status = l.text("Active · Caffeine is on")
            case .inactive: status = l.text("Waiting · Caffeine is off")
            case .stopped: status = l.text("Waiting · open Caffeine")
            case nil: status = l.text("Checking Caffeine")
            }
        }
        model.showStatus(status)
        let iconState = (model.enabled, status, model.issue)
        if let previous = lastIconState, previous == iconState { return }
        lastIconState = iconState
        let image = NSImage(systemSymbolName: model.enabled ? "moon.zzz.fill" : "moon.zzz", accessibilityDescription: "OLED Idle")
        image?.isTemplate = true
        image?.size = NSSize(width: 19, height: 19)
        item?.button?.image = image
        item?.button?.contentTintColor = model.issue != nil ? .systemOrange : nil
        item?.button?.toolTip = "OLED Idle — \(model.status)\n" + l.text("Left-click: enable / pause. Right-click: menu.")
        item?.button?.setAccessibilityLabel("OLED Idle")
        item?.button?.setAccessibilityValue(model.status)
    }
    private func setError(_ message: String) {
        if model.issue != message { logger.write(message) }
        model.setIssue(message)
        refreshStatus()
    }
    private func showMenu() {
        guard let button = item.button else { return }
        let menu = NSMenu()
        let status = menu.addItem(withTitle: model.status, action: nil, keyEquivalent: "")
        status.isEnabled = false
        if let issue = model.issue {
            let row = menu.addItem(withTitle: issue, action: nil, keyEquivalent: "")
            row.isEnabled = false
        }
        menu.addItem(.separator())
        for (title, action, key) in [
            (model.enabled ? l.text("Pause") : l.text("Enable"), #selector(toggle), ""),
            (l.text("Black out now"), #selector(blackoutNow), ""),
            (l.text("Settings…"), #selector(showSettings), ",")
        ] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: key).target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: l.text("Open log…"), action: #selector(openLog), keyEquivalent: "").target = self
        menu.addItem(withTitle: l.text("Quit"), action: #selector(quit), keyEquivalent: "q").target = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 5), in: button)
    }

    @objc private func showSettings() {
        blackout.dismiss()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 650),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "OLED Idle"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.center()
            settingsWindow = window
        }
        model.displays = DisplayInfo.connected()
        model.refreshLogin()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return true
    }
    func applicationDidResignActive(_ notification: Notification) { blackout.applicationResignedActive() }
    func applicationDidBecomeActive(_ notification: Notification) { model.refreshLogin() }
    @objc private func openLog() { NSWorkspace.shared.open(logger.url) }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        terminating = true
        timer?.invalidate()
        probe.cancel()
        blackout.dismiss(restoreFocus: false)
        try? power.setActive(false)
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        logger.write("Exited; assertions released.")
    }
}
