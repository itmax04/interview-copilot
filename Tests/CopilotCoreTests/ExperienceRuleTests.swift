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
        #expect(s.contains("Do not invent employer names, exact dates, counts, percentages or any other specific numbers about X"))
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
}
