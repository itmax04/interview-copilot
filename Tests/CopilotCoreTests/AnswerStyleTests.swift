import Foundation
import Testing
@testable import CopilotCore

@Suite("Стиль ответа — COPILOT-09 этап 3")
struct AnswerStyleTests {
    @Test func standardStyleKeepsThePreviousRuleWordForWord() {
        // Прежние строки промпта (0.8.0): стандарт не меняет ни поведение, ни кэш промпта.
        let interview = PromptBuilder.system(profile: PromptScenarios.sampleProfile, redactPII: true)
        #expect(interview.contains("- First line: the core answer in one short sentence in **bold**, so the candidate can start speaking at once. Then 2–5 short bullet points with details, at most 80 words in total. No preamble, no headings."))
        #expect(!interview.contains("Tone:"))
        let regular = PromptBuilder.system(profile: nil, redactPII: true, session: SessionPrompt(type: .regular))
        #expect(regular.contains("- First line: the core of what to say in one short sentence in **bold**. Then 2–5 short bullet points with details, arguments or numbers, at most 80 words in total. No preamble, no headings."))
        // Явный стандарт — то же самое, что без сессии.
        #expect(PromptBuilder.system(profile: PromptScenarios.sampleProfile, redactPII: true, session: SessionPrompt(style: .standard)) == interview)
    }

    @Test func formatsLengthsAndTonesChangeOnlyTheFormRule() {
        let script = AnswerStyle(format: .script, length: .short, tone: .formal).formatRule()
        #expect(script.contains("No bullet points, no bold") && script.contains("At most 40 words"))
        #expect(script.contains("Tone: formal"))
        let bullets = AnswerStyle(format: .bullets, length: .detailed).formatRule()
        #expect(bullets.contains("Only 3–7 short bullet points") && bullets.contains("At most 150 words") && bullets.contains("No paragraph of prose"))
        let friendly = AnswerStyle(tone: .friendly).formatRule()
        #expect(friendly.contains("Tone: warm, friendly") && friendly.contains("at most 80 words"))
        let regular = AnswerStyle(format: .script).formatRule(subject: "the core of what to say")
        #expect(regular.contains("the core of what to say first"))

        let system = PromptBuilder.system(profile: PromptScenarios.sampleProfile, redactPII: true,
                                          session: SessionPrompt(style: AnswerStyle(format: .script, length: .short)))
        #expect(system.contains("At most 40 words") && !system.contains("2–5 short bullet points"))
        // Правила надежности на месте.
        #expect(system.contains("never confirm") || system.contains("do not confirm"))
    }

    @Test func ownerInstructionsComeAfterTheStyleAndWin() {
        let s = PromptBuilder.system(profile: PromptScenarios.sampleProfile, redactPII: true, generalInstructions: "Відповідай списком.",
                                     session: SessionPrompt(instructions: "Коротко", style: AnswerStyle(format: .script)))
        let rule = try! #require(s.range(of: "A natural spoken script"))
        let owner = try! #require(s.range(of: "<owner_instructions>"))
        #expect(rule.upperBound < owner.lowerBound)
        #expect(s.contains("They take priority over the rules above about style, length, format, tone"))
    }

    @Test func detailedAnswersGetMoreTokens() {
        func tokens(_ style: AnswerStyle) -> Int {
            PromptBuilder.hintRequest(question: "Q", transcript: [], cards: [], baseCard: nil, profile: nil, redactPII: true,
                                      session: SessionPrompt(style: style)).maxTokens
        }
        #expect(tokens(.standard) == 400)
        #expect(tokens(AnswerStyle(length: .short)) == 400)
        #expect(tokens(AnswerStyle(length: .detailed)) == 800)
    }

    @Test func sessionStyleIsForThisCallOnlyAndDefaultsLiveInSettings() throws {
        var c = SessionConfig()
        #expect(c.effectiveStyle(default: AnswerStyle(tone: .formal)).tone == .formal)
        c.style = AnswerStyle(format: .bullets)
        #expect(c.effectiveStyle(default: AnswerStyle(tone: .formal)) == AnswerStyle(format: .bullets))
        #expect(c.defaultsForNext().style == nil)
        let decoded = try JSONDecoder().decode(SessionConfig.self, from: JSONEncoder().encode(c))
        #expect(decoded.style == AnswerStyle(format: .bullets))
        // Старые файлы — без стиля; неизвестное значение — стандарт по полю.
        #expect(try JSONDecoder().decode(SessionConfig.self, from: Data(#"{"type":"regular"}"#.utf8)).style == nil)
        let odd = try JSONDecoder().decode(AnswerStyle.self, from: Data(#"{"format":"poem","length":"short"}"#.utf8))
        #expect(odd == AnswerStyle(length: .short))
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).answerStyle == .standard)
    }

    @Test func sessionJobReplacesProfileJob() {
        var c = SessionConfig()
        let p = Profile(name: "p", resume: "r", job: "старая вакансия")
        #expect(c.applyingJob(to: p).job == "старая вакансия")
        c.jobDescription = "  Senior iOS  "
        c.company = "ФинБанк"
        #expect(c.applyingJob(to: p).job == "Компания: ФинБанк\n\nSenior iOS")
        #expect(c.applyingJob(to: p).resume == "r")
    }

    @Test func shapeHelpersCountWordsBulletsAndProse() {
        let text = "**Сім років в iOS.**\n- Банк на 1,2 млн\n• SwiftUI\n1. CI\n\nПідсумок одним реченням."
        #expect(AnswerShape.words(text) == 13)
        #expect(AnswerShape.bulletCount(text) == 3)
        #expect(AnswerShape.proseLines(text) == 2)
        #expect(AnswerShape.words("— **, -") == 0)
    }

    @Test(arguments: StylePreviewQuestion.allCases)
    func previewQuestionsExistInEveryLanguage(q: StylePreviewQuestion) {
        let uk = q.text(language: "uk"), ru = q.text(language: "ru"), en = q.text(language: "en")
        #expect(Set([uk, ru, en]).count == 3)
        #expect(q.text(language: "de") == en)
        #expect(q.regularText(language: "uk") != uk)
        #expect([uk, ru, en, q.regularText(language: "ru")].allSatisfy { $0.hasSuffix("?") || $0.hasSuffix(".") })
    }
}
