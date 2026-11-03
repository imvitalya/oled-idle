import Foundation

enum AppLanguage: String, Codable, CaseIterable {
    case system, en, ru
    func resolved(preferred: [String] = Locale.preferredLanguages) -> String {
        guard self == .system else { return rawValue }
        for language in preferred {
            let code = language.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
            if code == "ru" { return "ru" }
            if code == "en" { return "en" }
        }
        return "en"
    }
}

struct Localizer {
    let language: AppLanguage
    private let resources: URL
    init(language: AppLanguage, resources: URL = Bundle.main.resourceURL!) {
        self.language = language
        self.resources = resources
    }
    func text(_ key: String, _ args: CVarArg...) -> String {
        let code = language.resolved()
        let bundle = Bundle(url: resources.appendingPathComponent("\(code).lproj"))
        let format = bundle?.localizedString(forKey: key, value: key, table: nil) ?? key
        guard !args.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: code), arguments: args)
    }
}
