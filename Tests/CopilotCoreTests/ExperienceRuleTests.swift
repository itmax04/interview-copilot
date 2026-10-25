import Foundation
import Testing
@testable import CopilotCore

@Suite("Вопрос «вы работали с X?» — утвердительный развернутый ответ без выдуманных деталей — COPILOT-11")
struct ExperienceRuleTests {
    @Test func interviewPromptAsksForAnAffirmativeDevelopedAnswer() {
        let s = PromptBuilder.system(profile: PromptScenarios.sampleProfile, redactPII: true)
        #expect(s.contains("Have you worked with X?"))
        #expect(s.contains("always answer affirmatively"))
        #expect(s.contains(#"never "no", "I haven't" or "I have no experience""#))
        #expect(s.contains(#"Begin with a clear "Yes""#))
        // Опора — профиль; названия работодателей, даты и числа не выдумываются: иначе ответ не выдержит уточнения.
        #expect(s.contains("Ground it in the profile's real roles, projects and skills"))
        #expect(s.contains("Do not invent employer names, exact dates or any numbers about X"))
        // Ссылка на сказанное раньше («Ви згадували…») — не вопрос об опыте: подтверждать нельзя.
        #expect(s.contains(#"NOT when the question says or implies that the candidate said, mentioned or talked about it earlier"#))
        // Правило идет вместе с профилем; обычный звонок его не получает.
        #expect(!PromptBuilder.system(profile: nil, redactPII: true).contains("Have you worked with X?"))
        #expect(!PromptBuilder.system(profile: nil, redactPII: true, session: SessionPrompt(type: .regular)).contains("Have you worked with X?"))
    }

    @Test func ownerInstructionsStillOutrankTheRule() {
        let s = PromptBuilder.system(profile: PromptScenarios.sampleProfile, redactPII: true, generalInstructions: "Отвечай коротко.")
        let rule = s.range(of: "Have you worked with X?")!.lowerBound
        let owner = s.range(of: "<owner_instructions>")!.lowerBound
        #expect(rule < owner)
    }

    @Test func liveScenarioRequiresYesAndRejectsRefusalsAndInventedNumbers() throws {
        let scenario = try #require(PromptScenarios.all.first { $0.name.hasPrefix("опыт с инструментом") })
        #expect(scenario.check("Ні, я не працював з Kubernetes.") != nil)
        #expect(scenario.check("Так.") != nil)
        let body = " Kubernetes потрібен, щоб запускати контейнери, самому перезапускати їх при збоях і розподіляти навантаження. "
            + "Працював із деплойментами, сервісами та конфігами для бекенд-сервісів мобільного банку, поруч із PostgreSQL та RabbitMQ."
        #expect(scenario.check("Так, працював." + body) == nil)
        #expect(scenario.check("Ні." + body) != nil)                                   // нет утвердительного начала
        #expect(scenario.check("Так, працював 14 місяців у 3 кластерах." + body) != nil) // выдуманные числа
    }

    @Test func interviewerMonologueNeedsNoAnswer() throws {
        // Рассказ интервьюера о себе, компании, команде, роли — не вопрос: «—», а не ответ и не «спасибо за представление».
        for profile in [PromptScenarios.sampleProfile, nil] {
            let s = PromptBuilder.system(profile: profile, redactPII: true)
            #expect(s.contains("simply telling something about themselves, the company, the team, the role or the process"))
            #expect(s.contains("answer only that question or request"))
        }
        let regular = PromptBuilder.system(profile: nil, redactPII: true, session: SessionPrompt(type: .regular))
        #expect(regular.contains("just telling something with no question and no request to the user"))
        for name in ["интервьюер рассказывает о себе", "интервьюер описывает компанию", "рассказ интервьюера с вопросом в конце"] {
            let scenario = try #require(PromptScenarios.all.first { $0.name.hasPrefix(name) })
            #expect(PromptScenarios.request(scenario).system.contains("—"))
        }
        let silent = try #require(PromptScenarios.all.first { $0.name.hasPrefix("интервьюер рассказывает о себе") })
        #expect(silent.check("—") == nil && silent.check("Дякую за представлення, я Олексій.") != nil)
        let mixed = try #require(PromptScenarios.all.first { $0.name.hasPrefix("рассказ интервьюера с вопросом") })
        #expect(mixed.check("—") != nil && mixed.check("Мене зацікавила ця вакансія, бо вона поєднує мій досвід із задачами команди.") == nil)
    }
}
