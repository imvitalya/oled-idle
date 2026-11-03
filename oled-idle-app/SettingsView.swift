import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var model: AppModel
    private var l: Localizer { model.localizer }
    private let accent = Color(red: 0.32, green: 0.58, blue: 0.94)
    private let minutesFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = 1
        f.maximum = 180
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text("OLED Idle").font(.system(size: 24, weight: .semibold))
                    Text(l.text("Your screen rests. Your work continues.")).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.enabled ? l.text("Pause") : l.text("Enable")) { model.onToggle?() }
                    .buttonStyle(.borderedProminent).tint(accent).controlSize(.large)
            }.padding(24)
            HStack(spacing: 7) {
                Circle().fill(model.enabled ? Color.green : Color.secondary).frame(width: 7, height: 7)
                Text(model.status).font(.callout)
                Spacer()
            }.padding(.horizontal, 26).padding(.bottom, 15)
            Divider()
            TabView {
                general.tabItem { Label(l.text("General"), systemImage: "moon") }
                displays.tabItem { Label(l.text("Displays"), systemImage: "display.2") }
                controls.tabItem { Label(l.text("Controls"), systemImage: "slider.horizontal.3") }
            }.padding(.top, 16).padding(.horizontal, 18)
            if let issue = model.issue {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(issue).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button(l.text("Retry check")) { model.onRetry?() }
                }.padding(12).background(Color.orange.opacity(0.08)).cornerRadius(8).padding(.horizontal, 24)
            }
            Divider().padding(.top, 12)
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(l.text("Exit blackout: Esc or a click")).font(.caption)
                    Text(l.text("Left-click the moon to enable or pause")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(l.text("Black out now")) { model.onBlackout?() }.controlSize(.large)
                    .disabled(model.isRecordingShortcut)
            }.padding(20)
        }.frame(width: 650, height: 650).background(Color(nsColor: .windowBackgroundColor)).tint(accent)
            .environment(\.locale, Locale(identifier: model.preferences.language.resolved()))
    }

    private var general: some View {
        Form {
            Section {
                Picker(l.text("Mode"), selection: $model.preferences.mode) {
                    ForEach(OperatingMode.allCases, id: \.self) { Text(l.text($0.titleKey)).tag($0) }
                }
                Text(model.preferences.mode == .standalone
                    ? l.text("While enabled, the app keeps your Mac and displays awake. Caffeine is not required.")
                    : l.text("Automatic blackout runs only while Caffeine is active. Manual blackout is always available."))
                    .font(.callout).foregroundStyle(.secondary)
                if model.preferences.mode == .caffeine {
                    Button(l.text("Automation permissions…")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                    }
                }
            }
            Section {
                HStack {
                    Text(l.text("Black out after inactivity"))
                    Spacer()
                    TextField(l.text("Minutes"), value: $model.preferences.idleMinutes, formatter: minutesFormatter)
                        .labelsHidden().frame(width: 55).multilineTextAlignment(.trailing)
                        .accessibilityLabel(l.text("Minutes of inactivity"))
                    Text(l.text("min"))
                    Stepper(l.text("Minutes"), value: $model.preferences.idleMinutes, in: 1...180)
                        .labelsHidden().fixedSize()
                }
                Text(l.text("1–180 minutes without mouse or keyboard input. Leaving blackout starts a fresh interval."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                Text(l.text("Black OLED pixels stop emitting light. This shows a black image; it does not power off the monitor."))
                    .font(.callout).foregroundStyle(.secondary)
                Text(l.text("Manual locking and macOS security policies still apply."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private var displays: some View {
        Form {
            Section {
                Toggle(l.text("Black out all displays"), isOn: $model.preferences.allDisplays)
                Text(l.text("Newly connected displays are included automatically."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section(l.text("Connected displays · top to bottom")) {
                ForEach(Array(model.displays.enumerated()), id: \.element.id) { index, display in
                    Toggle(isOn: Binding(get: {
                        model.preferences.allDisplays || model.preferences.displayIDs.contains(display.id)
                    }, set: { selected in
                        if selected { model.preferences.displayIDs.append(display.id) }
                        else { model.preferences.displayIDs.removeAll { $0 == display.id } }
                    })) {
                        HStack(spacing: 10) {
                            Image(systemName: "display").font(.title2).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(index + 1). \(display.name)")
                                Text(display.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.disabled(model.preferences.allDisplays)
                }
                if model.displays.isEmpty { Text(l.text("No displays available")).foregroundStyle(.secondary) }
            }
            if !model.preferences.allDisplays && model.preferences.selectedDisplays(from: model.displays.map(\.id)).isEmpty {
                Text(l.text("Select at least one display. Blackout is unavailable while the selection is empty."))
                    .font(.callout).foregroundStyle(.orange)
            }
        }.formStyle(.grouped)
    }

    private var controls: some View {
        Form {
            Section {
                Toggle(l.text("Also exit when the mouse moves"), isOn: $model.preferences.wakeOnMouseMove)
                Text(l.text("Esc and clicks always work. Accidental mouse movement does not dismiss blackout by default."))
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Text(l.text("Blackout shortcut"))
                    Spacer()
                    ShortcutRecorder(shortcut: model.preferences.shortcut,
                        isRecording: $model.isRecordingShortcut, localizer: l,
                        onCapture: { model.preferences.shortcut = $0 },
                        onInvalid: { model.invalidShortcut = true })
                        .frame(minWidth: 145, maxWidth: 200, minHeight: 26)
                    if model.isRecordingShortcut {
                        Button(l.text("Cancel")) { model.isRecordingShortcut = false }
                    } else {
                        Button(l.text("Clear")) { model.preferences.shortcut = .disabled }
                            .disabled(model.preferences.shortcut.isDisabled)
                    }
                }
                Text(l.text(model.invalidShortcut
                    ? "Use Command, Control or Option with a key, or an F key."
                    : "Click, then press your shortcut. Escape cancels."))
                    .font(.callout).foregroundStyle(model.invalidShortcut ? Color.orange : Color.secondary)
                if let issue = model.shortcutIssue { Text(issue).font(.callout).foregroundStyle(.orange) }
            }
            Section {
                Picker(l.text("Language"), selection: $model.preferences.language) {
                    Text(l.text("System language")).tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.en)
                    Text("Русский").tag(AppLanguage.ru)
                }
            }
            Section {
                Toggle(l.text("Launch at login"), isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                Toggle(l.text("Enable protection when the app starts"), isOn: $model.preferences.startEnabled)
                Text(l.text("If the second switch is off, the app starts paused."))
                    .font(.callout).foregroundStyle(.secondary)
                if model.loginNeedsApproval {
                    Button(l.text("Allow in macOS Login Items…")) { SMAppService.openSystemSettingsLoginItems() }
                }
                if let issue = model.loginIssue { Text(issue).font(.callout).foregroundStyle(.orange) }
            }
        }.formStyle(.grouped)
    }
}
