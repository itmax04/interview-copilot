import CopilotCore
import Testing

@Suite("OutputSanityGuard — защита от случайных букв, смеси языков и деградации вывода")
struct OutputSanityGuardTests {
    @Test func validUkrainianWithTechTermsPasses() {
        let guarder = OutputSanityGuard(config: .init(expectedLanguage: "uk", requireUnderstoodLine: true))
        let text = """
        ❓ Яку архітектуру ви обирали для iOS-застосунку?
        **Обираю модульну архітектуру на базі SwiftUI та TCA.**
        • Окремі модулі для UI-тестів, мережі (HTTP/TCP) та PostgreSQL-кешу.
        • Під час код-рев'ю перевіряємо контракти між шарами.
        """
        #expect(guarder.check(text, isFinal: false) == nil)
        #expect(guarder.check(text, isFinal: true) == nil)
    }

    @Test func validRussianWithTechTermsPasses() {
        let guarder = OutputSanityGuard(config: .init(expectedLanguage: "ru", requireUnderstoodLine: true))
        let text = """
        ❓ Как вы организуете код в большом проекте?
        **Делю проект на независимые модули с чёткими границами.**
        • Отделяю бизнес-логику от сетевого слоя и базы PostgreSQL.
        • Покрываю критичные пути unit-тестами и проверяю на code review.
        """
        #expect(guarder.check(text, isFinal: true) == nil)
    }

    @Test func noAnswerMarkerAlwaysPasses() {
        let guarder = OutputSanityGuard(config: .init(expectedLanguage: "uk", requireUnderstoodLine: true))
        #expect(guarder.check("—", isFinal: true) == nil)
    }

    @Test func catchesUkrainianInRussianAnswerFromH1() {
        // Реальный дефект из живой проверки H-1 (A.1): модель смешала русский и украинский с диакритикой.
        let guarder = OutputSanityGuard(config: .init(expectedLanguage: "ru", requireUnderstoodLine: true))
        let mixed = """
        ❓ Как вы организуете код?
        Я делю код на логические модули.
        • Внутри модуля застосовую патерн «чистої архітектури»: шар домену, сервісний шар.
        • Використовую інтерфейси та абстракції, дотримуюсь єдиного стилю.
        """
        #expect(guarder.check(mixed, isFinal: false) == .languageMix)
    }

    @Test func catchesRussianInUkrainianAnswer() {
        let guarder = OutputSanityGuard(config: .init(expectedLanguage: "uk", requireUnderstoodLine: false))
        let mixed = "Я использую отдельные модули, чтобы контролировать обычные ошибки в системе."
        #expect(guarder.check(mixed, isFinal: false) == .languageMix)
    }

    @Test func catchesForeignScriptAndReplacementChar() {
        let guarder = OutputSanityGuard(config: .init(expectedLanguage: "uk"))
        #expect(guarder.check("Відповідь про договір 法律条文 та строки.", isFinal: false) == .foreignScript)
        #expect(guarder.check("Відповідь з битим символом \u{FFFD} у тексті.", isFinal: false) == .foreignScript)
    }

    @Test func catchesMixedScriptInsideSingleWord() {
        let guarder = OutputSanityGuard(config: .init(expectedLanguage: "ru"))
        #expect(guarder.check("В этом случае примenение нормы статьи обязательно.", isFinal: false) == .mixedWordScript)
    }

    @Test func catchesStrayCombiningMarksAfterNFC() {
        let guarder = OutputSanityGuard(config: .init(expectedLanguage: "ru"))
        let broken = "Обычный текст с артефактами отде́льну́ю и норму́."
        #expect(guarder.check(broken, isFinal: false) == .combiningMarks)
        // Обычные NFD-буквы й/ї/ё не должны вызывать ложное срабатывание.
        let nfdValid = "Український і російський йод ёлка".decomposedStringWithCanonicalMapping
        let anyLang = OutputSanityGuard(config: .init(expectedLanguage: nil))
        #expect(anyLang.check(nfdValid, isFinal: false) == nil)
    }

    @Test func catchesRepetitionLoop() {
        let guarder = OutputSanityGuard(config: .init(expectedLanguage: "ru"))
        let loop = "Согласно статье закона " + String(repeating: "срок давности составляет ", count: 3)
        #expect(guarder.check(loop, isFinal: false) == .repetitionLoop)
    }

    @Test func catchesConsonantGibberish() {
        let guarder = OutputSanityGuard(config: .init(expectedLanguage: "ru"))
        #expect(guarder.check("При ответе нужно учесть бвгджзклмн в договоре.", isFinal: false) == .consonantGibberish)
    }

    @Test func catchesPromptLeak() {
        let guarder = OutputSanityGuard(config: .init(expectedLanguage: "ru"))
        #expect(guarder.check("Согласно <materials> в договоре предусмотрен срок.", isFinal: false) == .promptLeak)
    }

    @Test func catchesMissingUnderstoodLineOnFinalOnly() {
        let guarder = OutputSanityGuard(config: .init(expectedLanguage: "ru", requireUnderstoodLine: true))
        let noLine = "Ответ модели без первой строки с вопросительным знаком."
        #expect(guarder.check(noLine, isFinal: false) == nil)
        #expect(guarder.check(noLine, isFinal: true) == .missingUnderstoodLine)
    }
}
