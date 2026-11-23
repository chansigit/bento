import Foundation

enum BentoLanguage {
    static let choices = [("system", "跟随系统"), ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"),
                          ("en", "English"), ("ja", "日本語"), ("ko", "한국어"), ("fr", "Français"),
                          ("es", "Español"), ("vi", "Tiếng Việt"), ("sv", "Svenska"), ("ru", "Русский"),
                          ("nb", "Norsk bokmål"), ("fi", "Suomi"), ("de", "Deutsch"), ("it", "Italiano"), ("uk", "Українська"), ("sw", "Kiswahili"), ("pt-BR", "Português (Brasil)")]
    static func resolve(_ preference: String, preferred: [String] = Locale.preferredLanguages) -> String {
        let candidates = preference == "system" ? preferred : [preference]
        for candidate in candidates {
            let tag = candidate.replacingOccurrences(of: "_", with: "-").lowercased()
            if tag == "zh" || tag.hasPrefix("zh-") {
                if tag.contains("hans") { return "zh-Hans" }
                return tag.contains("hant") || tag.contains("-tw") || tag.contains("-hk") || tag.contains("-mo") ? "zh-Hant" : "zh-Hans"
            }
            let base = String(tag.split(separator: "-").first ?? "")
            if base == "pt" { return "pt-BR" }
            if base == "no" || base == "nn" { return "nb" }
            if choices.contains(where: { $0.0 == base && base != "system" }) { return base }
        }
        return "en"
    }
    static var current: String { resolve(UserDefaults.standard.string(forKey: "languageID") ?? "system") }
    static var locale: Locale { Locale(identifier: current) }
    static let changed = Notification.Name("BentoLanguageChanged")
    static let bundles: [String: Bundle] = {
        var result: [String: Bundle] = [:]
        for (id, _) in choices {
            if let path = Bundle.main.path(forResource: id, ofType: "lproj"), let bundle = Bundle(path: path) { result[id] = bundle }
        }
        return result
    }()
    static func text(_ key: String, language: String) -> String {
        bundles[language]?.localizedString(forKey: key, value: key, table: nil) ?? key
    }
}

/// Values remain arguments, so user filenames and window titles are never translated.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    let text = BentoLanguage.text(key, language: BentoLanguage.current)
    return arguments.isEmpty ? text : String(format: text, locale: BentoLanguage.locale, arguments: arguments)
}
