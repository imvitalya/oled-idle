import Foundation

@main
enum OLEDPreferencesTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
        checks += 1
    }
    static func main() throws {
        var prefs = Preferences()
        prefs.idleMinutes = -4
        expect(prefs.normalized().idleMinutes == 1, "negative delay cannot disable protection")
        prefs.idleMinutes = 10000
        expect(prefs.normalized().idleMinutes == 180, "excessive delay is bounded")
        let damaged = Data(#"{"idleMinutes":"broken","mode":"obsolete","wakeOnMouseMove":true}"#.utf8)
        let restored = try JSONDecoder().decode(Preferences.self, from: damaged).normalized()
        expect(restored.idleMinutes == 15 && restored.mode == .standalone, "damaged fields fall back independently")
        expect(restored.wakeOnMouseMove, "valid preferences survive another damaged field")
        expect(restored.language == .ru, "pre-language settings retain their existing Russian interface")
        prefs = Preferences()
        prefs.allDisplays = false
        prefs.displayIDs = ["top", "top", "unplugged"]
        expect(prefs.selectedDisplays(from: ["top", "bottom"]) == ["top"], "stable selection excludes other identical monitor")
        expect(prefs.selectedDisplays(from: ["bottom"]).isEmpty, "disconnected selection never blacks another screen")
        prefs.allDisplays = true
        expect(prefs.selectedDisplays(from: ["top", "bottom"]) == ["top", "bottom"], "all displays includes newly attached monitor")
        let suite = "local.oled-idle.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        prefs.mode = .caffeine
        prefs.idleMinutes = 23
        prefs.language = .en
        prefs.save(to: defaults)
        let loaded = Preferences.load(from: defaults)
        expect(loaded.mode == .caffeine && loaded.idleMinutes == 23, "settings persist through a new read")
        expect(!loaded.startEnabled, "persisted settings do not silently enable observation at launch")
        expect(loaded.language == .en, "chosen language persists")
        let custom = try JSONDecoder().decode(Preferences.self, from: Data(#"{"shortcut":{"keyCode":8,"modifiers":2048}}"#.utf8))
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(custom)) as! [String: Any]
        let combo = json["shortcut"] as? [String: Any]
        expect((combo?["keyCode"] as? Int) == 8 && (combo?["modifiers"] as? Int) == 2048,
               "custom Option+C survives a preference round trip")
        print("All \(checks) preference checks passed.")
    }
}
