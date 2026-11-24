import Testing
@testable import CopilotCore

@Suite("COPILOT-15 — word error rate for the stt-dense eval")
struct WordErrorRateTests {
    @Test("Case, punctuation and ё/е do not count as errors")
    func normalization() {
        #expect(WordErrorRate.errors(reference: "Расскажите, ПОЖАЛУЙСТА, о всём.", hypothesis: "расскажите пожалуйста о всем") == 0)
    }

    @Test("Substitution, insertion and deletion each cost one")
    func edits() {
        #expect(WordErrorRate.errors(reference: "a b c d", hypothesis: "a x c d") == 1)
        #expect(WordErrorRate.errors(reference: "a b c", hypothesis: "a b c d") == 1)
        #expect(WordErrorRate.errors(reference: "a b c", hypothesis: "a c") == 1)
    }

    @Test("A cut word counts as two errors against one reference word")
    func cutWord() {
        #expect(WordErrorRate.errors(reference: "через PostgreSQL сервис", hypothesis: "через пост Греску сервис") == 2)
    }

    @Test("Empty sides")
    func empty() {
        #expect(WordErrorRate.errors(reference: "", hypothesis: "a b") == 2)
        #expect(WordErrorRate.errors(reference: "a b", hypothesis: "") == 2)
    }
}
