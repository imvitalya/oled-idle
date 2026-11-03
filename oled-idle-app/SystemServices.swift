import AppKit
import IOKit
import Carbon

func inputIdleSeconds() -> Double? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    guard let value = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue() as? NSNumber else { return nil }
    let seconds = value.doubleValue / 1_000_000_000
    return seconds.isFinite && seconds >= 0 ? seconds : nil
}

final class CaffeineProbe {
    private var task: Process?
    var isRunning: Bool { task != nil }

    func read(_ completion: @escaping (CaffeineState?) -> Void) {
        guard task == nil else { return }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.intelliscapesolutions.caffeine").isEmpty else {
            completion(.stopped); return
        }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "with timeout of 10 seconds", "-e",
            "if application id \"com.intelliscapesolutions.caffeine\" is running then", "-e",
            "tell application id \"com.intelliscapesolutions.caffeine\" to get active", "-e", "else",
            "-e", "return \"stopped\"", "-e", "end if", "-e", "end timeout"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        task = process
        process.terminationHandler = { [weak self] process in
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let state = process.terminationStatus == 0 ? CaffeineState(scriptOutput: String(decoding: data, as: UTF8.self)) : nil
            DispatchQueue.main.async {
                guard let self = self, self.task === process else { return }
                self.task = nil
                completion(state)
            }
        }
        do {
            try process.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self, weak process] in
                guard let process = process, self?.task === process, process.isRunning else { return }
                process.terminate()
            }
        } catch { task = nil; completion(nil) }
    }
    func cancel() {
        let old = task
        task = nil
        if old?.isRunning == true { old?.terminate() }
    }
    deinit { cancel() }
}

final class GlobalHotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer -> OSStatus in
            guard let pointer = pointer, let event = event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr, identifier.signature == 0x4F4C4544, identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalHotKey>.fromOpaque(pointer).takeUnretainedValue()
            guard owner.reference != nil else { return OSStatus(eventNotHandledErr) }
            owner.onPress?()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(_ shortcut: Shortcut, localizer: Localizer = Localizer(language: .system)) -> String? {
        if let reference = reference { UnregisterEventHotKey(reference) }
        reference = nil
        guard !shortcut.isDisabled else { return nil }
        guard shortcut.isValid, let key = shortcut.keyCode else { return localizer.text("Use Command, Control or Option with a key, or an F key.") }
        guard handler != nil else { return localizer.text("Could not connect the global shortcut.") }
        let result = RegisterEventHotKey(key, shortcut.modifiers & Shortcut.allowedModifiers, EventHotKeyID(signature: 0x4F4C4544, id: 1),
                                         GetApplicationEventTarget(), 0, &reference)
        return result == noErr ? nil : localizer.text("Shortcut %@ is unavailable. Choose another combination.", shortcut.localizedTitle(using: localizer))
    }
    deinit {
        if let reference = reference { UnregisterEventHotKey(reference) }
        if let handler = handler { RemoveEventHandler(handler) }
    }
}

final class AppLog {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/OLED Idle.log")
    func write(_ message: String) {
        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !manager.fileExists(atPath: url.path) { manager.createFile(atPath: url.path, contents: nil) }
        guard let file = try? FileHandle(forWritingTo: url) else { return }
        defer { try? file.close() }
        if let end = try? file.seekToEnd(), end > 1_048_576 { try? file.truncate(atOffset: 0) }
        try? file.write(contentsOf: Data("\(Date()) \(message)\n".utf8))
    }
}
