import Foundation
import Testing
@testable import CopilotCore

@Suite("Язык интерфейса: таблица, меню, разбор, страницы — COPILOT-10")
struct LocalizationTests {
    static let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources").standardized
    static let english: [String: String] = {
        let url = resources.appendingPathComponent("en.lproj/Localizable.strings")
        return (NSDictionary(contentsOf: url) as? [String: String]) ?? [:]
    }()

    /// Английский в пределах теста: соседние тесты идут параллельно и остаются на русском.
    func inEnglish<T>(_ body: () throws -> T) rethrows -> T {
        try L10n.$scope.withValue(L10n.Scope(language: .en, table: Self.english), operation: body)
    }

    @Test func russianIsTheKeyAndEnglishComesFromTheTable() {
        L10n.$scope.withValue(L10n.Scope(language: .ru, table: ["Сегодня": "Today"])) {
            #expect(L10n.t("Сегодня") == "Сегодня")
            #expect(L10n.f("Ключ %lld", 2) == "Ключ 2")
            #expect(L10n.aiLanguageName == "Russian")
        }
        L10n.$scope.withValue(L10n.Scope(language: .en, table: ["Сегодня": "Today", "Ключ %lld": "Key %lld"])) {
            #expect(L10n.t("Сегодня") == "Today")
            #expect(L10n.f("Ключ %lld", 2) == "Key 2")
            // Нет перевода — русский текст, интерфейс не ломается.
            #expect(L10n.t("Новая строка") == "Новая строка")
            #expect(L10n.aiLanguageName == "English")
        }
    }

    @Test func tableIsCompleteAndFormatsMatch() throws {
        #expect(Self.english.count > 700)
        let spec = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:lld|ld|d|@|\.\d+f|f)"#)
        func specifiers(_ s: String) -> [String] {
            spec.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { (s as NSString).substring(with: $0.range) }.sorted()
        }
        for (ru, en) in Self.english {
            #expect(specifiers(ru) == specifiers(en), "\(ru) → \(en)")
            #expect(!en.isEmpty, "\(ru)")
        }
    }

    @Test func menuAndStatusLineFollowTheLanguage() {
        let russian = MenuLayout.sections(for: MenuState()).flatMap { $0 }
        #expect(russian.contains { $0.title == "Ответить сейчас" })
        inEnglish {
            let items = MenuLayout.sections(for: MenuState()).flatMap { $0 }
            #expect(items.contains { $0.title == "Answer now" })
            #expect(items.contains { $0.title == "Quit" })
            #expect(items.contains { $0.title == "Call language: Auto (UK/RU/EN)" })
            #expect(!items.contains { $0.title.range(of: "[А-Яа-я]", options: .regularExpression) != nil && $0.action != .status })
            let meter = UsageMeter(pricing: UsageMeterTests.pricing, storage: nil)
            #expect(meter.statusLine == "Today: $0.00 · Gemini: 0 req")
        }
    }

    @Test func titlesOfCoreTypesAreTranslated() {
        inEnglish {
            #expect(SessionType.interview.title == "Interview")
            #expect(AnswerMode.bankOnly.title == "Question bank only")
            #expect(HotkeyAction.answerNow.title == "Answer now")
            #expect(LLMError.http(status: 429, message: "").description == "rate limit (429)")
            #expect(QuestionBankError(line: 3, message: "x").description == "Question bank: error on line 3: x")
        }
    }

    @Test func reviewForTheOwnerIsWrittenInTheInterfaceLanguage() {
        var r = SessionRecord(id: "s", startedAt: Date(), source: "Zoom")
        r.config = SessionConfig()
        let ru = ReviewPrompt.summaryRequest(r, redactPII: true)
        #expect(ru.system.contains("Write in Russian"))
        inEnglish {
            let en = ReviewPrompt.summaryRequest(r, redactPII: true)
            #expect(en.system.contains("Write in English") && !en.system.contains("Russian"))
            let comments = ReviewPrompt.commentsRequest([], type: .interview, profile: nil, redactPII: true)
            #expect(comments.system.contains("comment in English") && comments.system.contains("[number]"))
            #expect(!comments.system.contains("[цифра]"))
            let ask = ReviewPrompt.askRequest(r, question: "What went wrong?", redactPII: true)
            #expect(ask.system.contains("in English"))
        }
    }

    @Test(arguments: ["Interviewer", "TestCall"])
    func localPagesHaveNoRussianLeftInEnglish(page: String) throws {
        let dir = Self.resources.appendingPathComponent(page)
        let html = try String(contentsOf: dir.appendingPathComponent("index.html"), encoding: .utf8)
        let table = PageLocalization.table(in: dir)
        #expect(!table.isEmpty)
        let english = PageLocalization.localize(html, table: table)
        #expect(english.contains("<html lang=\"en\">") && english.contains("window.L10N="))
        // Разметка: русского не осталось, кроме названий языков в списке.
        let head = String(english[..<english.range(of: "<script>window.L10N=")!.lowerBound])
            .replacingOccurrences(of: "Русский", with: "").replacingOccurrences(of: "Українська", with: "")
        #expect(head.range(of: "[А-Яа-яЁё]", options: .regularExpression) == nil, "\(page): \(head.prefix(200))")
        // Скрипт: у каждой строки T('…') есть перевод.
        let script = String(html[html.range(of: "<script>")!.lowerBound...])
        let calls = try NSRegularExpression(pattern: #"T\('((?:[^'\\]|\\.)*)'"#)
        let keys = calls.matches(in: script, range: NSRange(script.startIndex..., in: script)).map { (script as NSString).substring(with: $0.range(at: 1)) }
        #expect(keys.count > 10)
        for key in keys { #expect(table[key] != nil, "\(page): \(key)") }
        // Русский интерфейс — страница без изменений.
        #expect(PageLocalization.localize(html, table: [:]) == html)
    }
}
