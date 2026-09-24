import Foundation

final class AppLocalization {
    static let shared = AppLocalization()
    private let lock = NSLock()
    private var strings: [String: String] = [:]
    private var cacheLoaded = false
    let english: [String: String]
    let language: String
    let bundled: Bool
    static func base(_ identifier: String) -> String {
        let value = identifier.replacingOccurrences(of: "_", with: "-")
        if value.hasPrefix("zh") { return value.contains("Hant") || value.contains("TW") || value.contains("HK") ? "zh-Hant" : "zh-Hans" }
        return value.components(separatedBy: "-").first ?? "en"
    }
    init() {
        language = Self.base(Locale.preferredLanguages.first ?? "en")
        var root = Bundle.main.resourceURL?.appendingPathComponent("Localization")
        #if TESTING
        if let path = ProcessInfo.processInfo.environment["MACTIDY_LOCALIZATION_DIR"] { root = URL(fileURLWithPath: path) }
        #endif
        func read(_ code: String) -> [String: String]? {
            guard let url = root?.appendingPathComponent(code + ".json"), let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode([String: String].self, from: data)
        }
        english = read("en") ?? [:]
        let catalog = read(language)
        bundled = catalog != nil
        strings = catalog ?? english
        if !bundled, let data = try? Data(contentsOf: cacheURL), let cached = try? JSONDecoder().decode([String: String].self, from: data), Set(cached.keys) == Set(english.keys) { strings = cached; cacheLoaded = true }
    }
    var cacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacTidy/Translations/2.1-\(language).json")
    }
    var needsTranslation: Bool { !bundled && !cacheLoaded }
    func install(_ catalog: [String: String]) throws {
        guard Set(catalog.keys) == Set(english.keys) else { return }
        var checked = catalog
        for (key, value) in english where Self.tokens(value) != Self.tokens(catalog[key] ?? "") { checked[key] = value }
        let data = try JSONEncoder().encode(checked)
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: cacheURL, options: .atomic)
        lock.lock(); strings = checked; cacheLoaded = true; lock.unlock()
    }
    static func tokens(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "\\{[0-9]+\\}")
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range) }.sorted()
    }
    static func format(_ template: String, _ arguments: [Any]) -> String {
        let regex = try! NSRegularExpression(pattern: "\\{([0-9]+)\\}")
        var result = template
        for match in regex.matches(in: template, range: NSRange(template.startIndex..., in: template)).reversed() {
            guard let index = Int((template as NSString).substring(with: match.range(at: 1))), index < arguments.count, let range = Range(match.range, in: result) else { continue }
            let value: String
            if let number = arguments[index] as? NSNumber {
                let formatter = NumberFormatter(); formatter.numberStyle = .decimal; formatter.locale = .current
                value = formatter.string(from: number) ?? number.stringValue
            } else { value = String(describing: arguments[index]) }
            result.replaceSubrange(range, with: value)
        }
        return result
    }
    func text(_ key: String, _ arguments: [Any]) -> String {
        lock.lock(); let template = strings[key] ?? english[key] ?? key; lock.unlock()
        return Self.format(template, arguments)
    }
}
func L(_ key: String, _ arguments: Any...) -> String { AppLocalization.shared.text(key, arguments) }
