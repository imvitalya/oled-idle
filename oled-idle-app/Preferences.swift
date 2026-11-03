import Foundation

enum OperatingMode: String, Codable, CaseIterable {
    case standalone, caffeine
    var titleKey: String { self == .standalone ? "Standalone" : "With Caffeine" }
}

struct Preferences: Codable, Equatable {
    var idleMinutes = 15
    var mode: OperatingMode = .standalone
    var wakeOnMouseMove = false
    var allDisplays = true
    var displayIDs: [String] = []
    var startEnabled = false
    var shortcut: Shortcut = .controlOptionCommandB
    var language: AppLanguage = .system

    init() {}
    enum CodingKeys: String, CodingKey {
        case idleMinutes, mode, wakeOnMouseMove, allDisplays, displayIDs, startEnabled, shortcut, language
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        idleMinutes = (try? c.decode(Int.self, forKey: .idleMinutes)) ?? 15
        mode = (try? c.decode(OperatingMode.self, forKey: .mode)) ?? .standalone
        wakeOnMouseMove = (try? c.decode(Bool.self, forKey: .wakeOnMouseMove)) ?? false
        allDisplays = (try? c.decode(Bool.self, forKey: .allDisplays)) ?? true
        displayIDs = (try? c.decode([String].self, forKey: .displayIDs)) ?? []
        startEnabled = (try? c.decode(Bool.self, forKey: .startEnabled)) ?? false
        shortcut = (try? c.decode(Shortcut.self, forKey: .shortcut)) ?? .controlOptionCommandB
        // Existing v2 settings came from the Russian-only UI; fresh installs use System.
        language = (try? c.decode(AppLanguage.self, forKey: .language)) ?? (c.contains(.language) ? .system : .ru)
    }
    func normalized() -> Preferences {
        var copy = self
        copy.idleMinutes = min(180, max(1, idleMinutes))
        copy.displayIDs = Array(Set(displayIDs.filter { !$0.isEmpty })).sorted()
        copy.shortcut = shortcut.normalized()
        return copy
    }
    func selectedDisplays(from connected: [String]) -> [String] {
        connected.filter { allDisplays || displayIDs.contains($0) }
    }
    static func load(from defaults: UserDefaults = .standard) -> Preferences {
        guard let data = defaults.data(forKey: "preferences.v2"),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value.normalized()
    }
    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(normalized()) { defaults.set(data, forKey: "preferences.v2") }
    }
}
