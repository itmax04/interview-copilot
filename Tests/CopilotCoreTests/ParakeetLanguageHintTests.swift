@testable import CopilotCore
import FluidAudio
import Testing

@Suite("COPILOT-17 R-01 — подсказка языка Parakeet")
struct ParakeetLanguageHintTests {
    @Test func fixedLanguagesMapToTheScriptFilter() {
        #expect(ParakeetEngine.languageHint(for: "uk") == .ukrainian)
        #expect(ParakeetEngine.languageHint(for: "ru") == .russian)
        #expect(ParakeetEngine.languageHint(for: "en") == .english)
        #expect(ParakeetEngine.languageHint(for: "UK") == .ukrainian)
    }

    @Test func autoAndUnknownGiveNoHint() {
        #expect(ParakeetEngine.languageHint(for: nil) == nil)
        #expect(ParakeetEngine.languageHint(for: "auto") == nil)
        #expect(ParakeetEngine.languageHint(for: "de") == nil)
        #expect(ParakeetEngine.languageHint(for: "") == nil)
    }
}
