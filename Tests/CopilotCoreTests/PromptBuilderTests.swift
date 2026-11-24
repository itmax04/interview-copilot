import Foundation
import Testing
@testable import CopilotCore

@Suite("COPILOT-15 P-10 — understood-question line (AC-08)")
struct UnderstoodLineTests {
    private func hint() -> LLMRequest {
        PromptBuilder.hintRequest(question: "Розкажіть про Combine", transcript: [], cards: [], baseCard: nil,
                                  profile: nil, redactPII: false)
    }

    @Test("The hint prompt requires the restating first line, forbids correction and invention")
    func hintRequiresLine() {
        let s = hint().system
        #expect(s.contains("the first line is \"❓ \""))
        #expect(s.contains("do not correct the wording"))
        #expect(s.contains("without the \"❓\" line"))
    }

    @Test("The strong-model path and the screenshot (coding) path are unchanged")
    func otherPathsUnchanged() {
        let strong = PromptBuilder.strongRequest(question: "q q q", transcript: [], cards: [], baseCard: nil, profile: nil, redactPII: false)
        #expect(!strong.system.contains("❓"))
        #expect(!PromptBuilder.screenshotRequest(image: Data([1]), language: nil).system.contains("❓"))
    }

    @Test("The rule applies in regular calls too and stays before the owner's instructions")
    func regularCall() {
        let r = PromptBuilder.system(profile: nil, redactPII: false, generalInstructions: "Be brief",
                                     session: SessionPrompt(type: .regular), understoodLine: true)
        let rule = r.range(of: "Output format of the hint")
        let owner = r.range(of: "Be brief")
        #expect(rule != nil && owner != nil && rule!.lowerBound < owner!.lowerBound)
    }

    @Test("split: the line and the answer, streaming partials, no line, the no-answer dash")
    func split() {
        let full = UnderstoodLine.split("❓ Що таке Combine?\n**Суть.**\nДеталі")
        #expect(full.line == "❓ Що таке Combine?")
        #expect(full.rest == "**Суть.**\nДеталі")
        let partial = UnderstoodLine.split("❓ Що таке Comb")
        #expect(partial.line == "❓ Що таке Comb")
        #expect(partial.rest.isEmpty)
        let none = UnderstoodLine.split("**Суть.**\nДеталі")
        #expect(none.line == nil && none.rest == "**Суть.**\nДеталі")
        #expect(UnderstoodLine.split("—").line == nil)
        #expect(UnderstoodLine.answer("❓ q\n\nanswer") == "answer")
    }

    @Test("split tolerates U+FE0F, markdown emphasis and leading whitespace; the line comes back clean")
    func splitTolerant() {
        let variants = [
            "❓\u{FE0F} Що таке Combine?\nВідповідь",
            "**❓ Що таке Combine?**\nВідповідь",
            "**❓\u{FE0F} Що таке Combine?**\nВідповідь",
            "  \n_❓ Що таке Combine?_\nВідповідь",
            "*❓ Що таке Combine?*\nВідповідь",
            "❓Що таке Combine?\nВідповідь",
            "❓ **Що таке Combine?**\nВідповідь",
        ]
        for v in variants {
            let r = UnderstoodLine.split(v)
            #expect(r.line == "❓ Що таке Combine?", "\(v)")
            #expect(r.rest == "Відповідь", "\(v)")
            #expect(UnderstoodLine.answer(v) == "Відповідь", "\(v)")
            #expect(UnderstoodLine.state(v) == "present", "\(v)")
        }
        // Потоковый кусок с открытым `**` и без перевода строки.
        #expect(UnderstoodLine.split("**❓ Що таке Comb").line == "❓ Що таке Comb")
        // Эмодзи не в начале — это не строка пересказа.
        #expect(UnderstoodLine.split("Відповідь ❓ далі").line == nil)
    }

    @Test("state: present, absent, malformed (marker without text); the no-answer dash is absent")
    func stateLabel() {
        #expect(UnderstoodLine.state("❓ q\na") == "present")
        #expect(UnderstoodLine.state("**Суть.**\nДеталі") == "absent")
        #expect(UnderstoodLine.state("—") == "absent")
        #expect(UnderstoodLine.state("❓\u{FE0F}\nДеталі") == "malformed")
        #expect(UnderstoodLine.state("**❓**\nДеталі") == "malformed")
    }

    @Test("The prompt bans topics from earlier turns or the profile in the line; the experience 'Yes' follows the line")
    func promptRules() {
        let s = hint().system
        #expect(s.contains("never bring into it a topic, project"))
        let withProfile = PromptBuilder.system(profile: Profile(name: "p"), redactPII: false, understoodLine: true)
        #expect(withProfile.contains("Begin the first line of the answer itself (after the"))
    }

    @Test("Eval helpers look at the answer, not at the understood line")
    func evalHelpers() {
        #expect(PromptScenarios.firstLine("❓ Так, питання\n**Combine — це…**") == "combine — це…")
        #expect(!PromptScenarios.confirmsPremise("❓ Так, ви працювали з Kafka?\nНі, не працював"))
    }
}
