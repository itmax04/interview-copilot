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

    @Test("Eval helpers look at the answer, not at the understood line")
    func evalHelpers() {
        #expect(PromptScenarios.firstLine("❓ Так, питання\n**Combine — це…**") == "combine — це…")
        #expect(!PromptScenarios.confirmsPremise("❓ Так, ви працювали з Kafka?\nНі, не працював"))
    }
}
