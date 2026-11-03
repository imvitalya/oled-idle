import Foundation

@main
enum OLEDShortcutLanguageTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
        checks += 1
    }
    static func main() throws {
        let decoder = JSONDecoder()
        for (legacy, key, flags): (String, UInt32?, UInt32) in [
            ("controlOptionCommandB", 11, 6400), ("controlOptionCommandO", 31, 6400),
            ("controlOptionB", 11, 6144), ("disabled", nil, 0)
        ] {
            let shortcut = try decoder.decode(Shortcut.self, from: JSONEncoder().encode(legacy))
            expect(shortcut.keyCode == key && shortcut.modifiers == flags, "old \(legacy) migrates without changing its keys")
        }
        expect(!Shortcut(keyCode: 0, modifiers: 0).isValid, "bare letter cannot steal normal typing")
        expect(!Shortcut(keyCode: 0, modifiers: Shortcut.shift).isValid, "shift letter cannot steal capital typing")
        expect(Shortcut(keyCode: 122, modifiers: 0).isValid, "unmodified F1 is supported")
        expect(Shortcut(keyCode: 8, modifiers: Shortcut.option).isValid, "single-modifier custom shortcut is supported")
        expect(!Shortcut(keyCode: 53, modifiers: Shortcut.command).isValid, "Escape remains available for cancellation")
        expect(!Shortcut(keyCode: 56, modifiers: Shortcut.option).isValid, "modifier-only key is not captured")
        expect(!Shortcut(keyCode: 999, modifiers: Shortcut.command).isValid, "unknown key code is rejected")
        expect(Shortcut(keyCode: 8, modifiers: Shortcut.option | (1 << 20)).normalized().modifiers == 2048,
               "unsupported modifier bits cannot reach Carbon")
        let custom = Shortcut(keyCode: 8, modifiers: Shortcut.command | Shortcut.shift)
        let roundTrip = try decoder.decode(Shortcut.self, from: JSONEncoder().encode(custom))
        expect(roundTrip == custom, "custom shortcut persists")
        let invalid = try decoder.decode(Shortcut.self, from: Data(#"{"keyCode":0,"modifiers":0}"#.utf8))
        expect(invalid.isDisabled, "corrupt stored bare-letter shortcut becomes disabled")
        expect(AppLanguage.system.resolved(preferred: ["de-DE", "ru_RU"]) == "ru", "system language finds supported Russian fallback")
        expect(AppLanguage.system.resolved(preferred: ["en-GB", "ru"]) == "en", "system language respects preference order")
        expect(AppLanguage.system.resolved(preferred: ["ja-JP"]) == "en", "unsupported system locale falls back to English")
        expect(AppLanguage.ru.resolved(preferred: ["en"]) == "ru", "explicit language overrides system")
        let english = Localizer(language: .en)
        let russian = Localizer(language: .ru)
        expect(english.text("Settings…") == "Settings…", "English resource loads")
        expect(russian.text("Settings…") == "Настройки…", "Russian resource loads")
        expect(Shortcut(keyCode: 49, modifiers: Shortcut.control).localizedTitle(using: russian) == "⌃ Пробел", "named key uses selected Russian language")
        expect(Shortcut(keyCode: 83, modifiers: Shortcut.option).localizedTitle(using: russian) == "⌥ Цифр. 1", "keypad key uses selected Russian language")
        expect(russian.text("Active · blackout after %ld min of inactivity", 15) == "Активно · затемнение через 15 мин бездействия",
               "Russian status formats the chosen idle delay")
        expect(english.text("Shortcut %@ is unavailable. Choose another combination.", "⌥ C") == "Shortcut ⌥ C is unavailable. Choose another combination.",
               "English conflict message formats the shortcut")
        print("All \(checks) shortcut/language checks passed.")
    }
}
