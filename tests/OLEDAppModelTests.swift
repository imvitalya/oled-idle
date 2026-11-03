import Foundation

@main
enum OLEDAppModelTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
        checks += 1
    }
    static func main() {
        let suite = "local.oled-idle.model-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        var notifications = 0
        model.onPreferencesChange = { notifications += 1 }
        model.preferences.idleMinutes = 23
        expect(model.preferences.idleMinutes == 23 && notifications == 1, "changing a UI binding finishes and notifies once")
        expect(Preferences.load(from: defaults).idleMinutes == 23, "UI update persists to its preferences store")
        model.preferences.idleMinutes = 23
        expect(notifications == 1, "SwiftUI writing an unchanged binding does not restart observation")
        model.preferences.idleMinutes = -5
        expect(model.preferences.idleMinutes == 1 && notifications == 2, "invalid UI input normalizes without recursive updates")
        expect(Preferences.load(from: defaults).idleMinutes == 1, "normalized setting is saved")
        model.preferences.displayIDs = ["top", "top", "bottom"]
        expect(model.preferences.displayIDs == ["bottom", "top"] && notifications == 3, "display normalization produces one settings change")
        let restored = AppModel(defaults: defaults)
        expect(restored.preferences == model.preferences, "new settings model restores all saved values")
        var redraws = 0
        let subscription = model.objectWillChange.sink { redraws += 1 }
        model.showStatus("Active")
        model.showStatus("Active")
        model.setIssue(nil)
        expect(redraws == 1, "unchanged timer samples do not redraw open settings controls")
        model.setIssue("Disconnected")
        model.setIssue("Disconnected")
        model.setIssue(nil)
        expect(redraws == 3, "only real issue changes notify the settings UI")
        withExtendedLifetime(subscription) {}
        print("All \(checks) app-model checks passed.")
    }
}
