import AppKit
import IOKit.pwr_mgt
import SwiftUI
import Carbon

@main
enum OLEDSystemTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
        checks += 1
        print("PASS: \(name)")
    }
    static func assertionCount() -> Int {
        var value: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&value) == kIOReturnSuccess,
              let assertions = value?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return -1 }
        return (assertions[NSNumber(value: ProcessInfo.processInfo.processIdentifier)] ?? []).filter {
            ($0[kIOPMAssertionNameKey] as? String)?.hasPrefix("OLED Idle") == true
        }.count
    }
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let power = PowerManager()
        try power.setActive(true)
        expect(power.isActive && assertionCount() == 2, "real display and system assertions acquired")
        try power.setActive(true)
        expect(assertionCount() == 2, "repeated enable does not leak assertions")
        try power.setActive(false)
        expect(!power.isActive && assertionCount() == 0, "pause releases both system assertions")
        expect(inputIdleSeconds() != nil, "idle time available without Accessibility access")
        let displays = DisplayInfo.connected()
        expect(!displays.isEmpty, "display catalog has physical displays")
        expect(Set(displays.map(\.id)).count == displays.count, "same-model displays have distinct UUIDs")
        let first = GlobalHotKey()
        expect(first.register(.controlOptionCommandO) == nil, "global hotkey registers")
        var presses = 0
        first.onPress = { presses += 1 }
        var hotkeyEvent: EventRef?
        CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &hotkeyEvent)
        if let event = hotkeyEvent {
            var identifier = EventHotKeyID(signature: 0x4F4C4544, id: 1)
            SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              MemoryLayout<EventHotKeyID>.size, &identifier)
            SendEventToEventTarget(event, GetApplicationEventTarget())
            ReleaseEvent(event)
        }
        expect(presses == 1, "registered handler dispatches a Carbon hotkey event")
        let second = GlobalHotKey()
        expect(second.register(.controlOptionCommandO) != nil, "occupied hotkey reports conflict")
        _ = first.register(.disabled)
        expect(second.register(.controlOptionCommandO) == nil, "changing hotkey releases previous registration")
        _ = second.register(.disabled)

        if let index = CommandLine.arguments.firstIndex(of: "--render-settings"), CommandLine.arguments.count > index + 1 {
            let model = AppModel()
            model.displays = displays
            let view = NSHostingView(rootView: SettingsView(model: model))
            view.frame = NSRect(x: 0, y: 0, width: 650, height: 650)
            let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("No settings image") }
            view.cacheDisplay(in: view.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }

        if CommandLine.arguments.contains("--blackout") {
            let blackout = BlackoutController()
            var dismissals = 0
            blackout.onDismiss = { dismissals += 1 }
            expect(blackout.show(screens: displays.map(\.screen), wakeOnMouseMove: false), "blackout creates windows")
            expect(blackout.windows.count == displays.count, "every requested display gets one overlay")
            for (window, display) in zip(blackout.windows, displays) {
                expect(window.frame == display.screen.frame, "overlay uses full screen bounds")
                expect(window.isOpaque && !window.hasShadow, "opaque overlay has no shadow")
                let color = window.backgroundColor?.usingColorSpace(.sRGB)
                expect(color?.redComponent == 0 && color?.greenComponent == 0 && color?.blueComponent == 0,
                       "black pixels contain zero red, green and blue")
            }
            func move() {
                if let event = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: blackout.windows.first?.windowNumber ?? 0,
                    context: nil, eventNumber: 1, clickCount: 0, pressure: 0) { app.postEvent(event, atStart: false) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { move() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                expect(blackout.isActive, "mouse movement does not dismiss default blackout")
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: blackout.windows.first?.windowNumber ?? 0,
                    context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) {
                    app.postEvent(event, atStart: false)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                expect(!blackout.isActive && blackout.windows.isEmpty && dismissals == 1, "Escape event releases windows exactly once")
                blackout.dismiss()
                expect(dismissals == 1, "repeated dismissal does not rearm twice")
                expect(blackout.show(screens: [displays[0].screen], wakeOnMouseMove: true), "second blackout works after dismissal")
                move()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                expect(blackout.isActive, "launch grace ignores immediate pointer movement")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { move() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                expect(!blackout.isActive && dismissals == 2, "optional mouse-movement exit consumes actual AppKit event")
                _ = blackout.show(screens: [displays[0].screen], wakeOnMouseMove: false)
                blackout.update(screens: [])
                expect(!blackout.isActive && dismissals == 3, "disconnecting all selected displays dismisses blackout")
                _ = blackout.show(screens: [displays[0].screen], wakeOnMouseMove: false)
                blackout.applicationResignedActive()
                expect(!blackout.isActive && dismissals == 4, "switching app removes overlays before invisible input")
                print("All \(checks) system checks passed.")
                app.stop(nil)
            }
            app.run()
        } else { print("All \(checks) system checks passed. Visible blackout checks skipped.") }
    }
}
