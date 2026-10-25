import Foundation

/// Язык интерфейса — COPILOT-10. Ключ строки — русский текст (как в коде); английский — в `en.lproj/Localizable.strings`.
/// Русский интерфейс — ключ как есть. Переключение сразу: окна перерисовываются с новым языком (`LocalizedRoot` в приложении).
public enum L10n {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _language: InterfaceLanguage = .ru
    nonisolated(unsafe) private static var english: [String: String] = [:]

    /// Язык и таблица в пределах задачи — тесты идут параллельно и не должны менять язык друг другу.
    public struct Scope: Sendable {
        public var language: InterfaceLanguage
        public var table: [String: String]
        public init(language: InterfaceLanguage, table: [String: String]) {
            self.language = language.resolved(); self.table = table
        }
    }

    @TaskLocal public static var scope: Scope?

    /// Фактический язык (.ru или .en).
    public static var language: InterfaceLanguage {
        get { scope?.language ?? lock.withLock { _language } }
        set { lock.withLock { _language = newValue.resolved() } }
    }

    public static var isEnglish: Bool { language == .en }

    /// Локаль для SwiftUI (`\.locale`) и форматов дат.
    public static var locale: Locale { Locale(identifier: isEnglish ? "en" : "ru") }

    /// Английская таблица: из пакета приложения (`Contents/Resources/en.lproj`), иначе — из папки проекта
    /// (запуск из `.build`, снимки, тесты).
    public static func loadTable(bundle: Bundle = .main, fallbackDirectory: URL? = nil) {
        var url = bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en")
        if url == nil, let dir = fallbackDirectory {
            let candidate = dir.appendingPathComponent("en.lproj/Localizable.strings")
            if FileManager.default.fileExists(atPath: candidate.path) { url = candidate }
        }
        guard let url, let dict = NSDictionary(contentsOf: url) as? [String: String] else { return }
        lock.withLock { english = dict }
    }

    /// Таблица напрямую (тесты).
    public static func setTable(_ table: [String: String]) { lock.withLock { english = table } }

    public static var table: [String: String] { scope?.table ?? lock.withLock { english } }

    /// Перевод строки интерфейса; нет перевода — русский текст (виден, но не ломает интерфейс).
    public static func t(_ key: String) -> String {
        if let scope { return scope.language == .en ? (scope.table[key] ?? key) : key }
        return lock.withLock { _language == .en ? (english[key] ?? key) : key }
    }

    /// Строка с подстановкой: ключ — русский формат («Ключ %lld»), аргументы — как у `String(format:)`.
    public static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), locale: locale, arguments: args)
    }

    /// Язык, на котором ИИ пишет тексты для владельца (разбор, «Спросить ИИ»): язык интерфейса.
    public static var aiLanguageName: String { isEnglish ? "English" : "Russian" }
}
