import Foundation
import Testing
@testable import CopilotCore

/// COPILOT-18 D9: одноразовое «Уточнение голосом» — состояние, таймаут, решение для взведённой фразы, хоткей.
@Suite("Уточнение голосом одним разом — COPILOT-18 D9")
struct VoiceClarifyTests {
    private let t0 = Date(timeIntervalSince1970: 1_792_400_000)

    @Test func toggleArmsAndCancels() {
        var a = VoiceClarifyArm()
        #expect(!a.isArmed)
        let armed = a.toggle(now: t0)
        #expect(armed && a.isArmed)
        let cancelled = a.toggle(now: t0.addingTimeInterval(2))      // повторное нажатие отменяет
        #expect(!cancelled && !a.isArmed)
    }

    @Test func consumeIsOneShot() {
        var a = VoiceClarifyArm()
        let idle = a.consume(interrupted: false)                     // не взведён — ничего не расходуется
        #expect(!idle)
        a.toggle(now: t0)
        let first = a.consume(interrupted: false)
        #expect(first && !a.isArmed)
        let second = a.consume(interrupted: false)                   // следующая фраза — уже обычная
        #expect(!second)
    }

    @Test func interruptedPhraseKeepsArmed() {
        var a = VoiceClarifyArm()
        a.toggle(now: t0)
        let used = a.consume(interrupted: true)
        #expect(!used && a.isArmed)
    }

    @Test func timeoutDisarmsOnlyWhenOwnerSilent() {
        var a = VoiceClarifyArm()
        a.toggle(now: t0)
        let early = a.expire(now: t0.addingTimeInterval(14.9), ownerSpeaking: false)
        #expect(!early && a.isArmed)
        let speaking = a.expire(now: t0.addingTimeInterval(16), ownerSpeaking: true)   // владелец говорит — ждём конца фразы
        #expect(!speaking && a.isArmed)
        let late = a.expire(now: t0.addingTimeInterval(17), ownerSpeaking: false)
        #expect(late && !a.isArmed)
        let again = a.expire(now: t0.addingTimeInterval(30), ownerSpeaking: false)     // уже погас
        #expect(!again)
    }

    @Test func forcedTurnsPlainPhraseIntoClarification() {
        // Обычный detect молчит на фразу без маркеров, если вопрос старше 25 с; во взведённом режиме это поправка к вопросу.
        let text = "основні ознаки держави"
        #expect(OwnerQuestionDetector.detect(text: text, secondsSinceLastQuestion: 40, hasActiveQuestion: true) == .none)
        #expect(OwnerQuestionDetector.detectForced(text: text, secondsSinceLastQuestion: 40, hasActiveQuestion: true)
                == .clarifyLastQuestion(correction: text))
    }

    @Test func forcedKeepsDetectorDecisionWhenItSpeaks() {
        let text = "Тобто що таке держава?"
        let normal = OwnerQuestionDetector.detect(text: text, secondsSinceLastQuestion: 5, hasActiveQuestion: true)
        #expect(normal != .none)
        #expect(OwnerQuestionDetector.detectForced(text: text, secondsSinceLastQuestion: 5, hasActiveQuestion: true) == normal)
    }

    @Test func forcedFillerEmptyOrTooLongIsOrdinaryAnswer() {
        for active in [true, false] {
            #expect(OwnerQuestionDetector.detectForced(text: "так, секунду", secondsSinceLastQuestion: 5, hasActiveQuestion: active) == .none)
            #expect(OwnerQuestionDetector.detectForced(text: "", secondsSinceLastQuestion: 5, hasActiveQuestion: active) == .none)
            #expect(OwnerQuestionDetector.detectForced(text: "  \n ", secondsSinceLastQuestion: nil, hasActiveQuestion: active) == .none)
            let tooLong = Array(repeating: "слово", count: OwnerQuestionDetector.forcedMaxWords + 1).joined(separator: " ")
            #expect(OwnerQuestionDetector.detectForced(text: tooLong, secondsSinceLastQuestion: 5, hasActiveQuestion: active) == .none)
        }
    }

    @Test func forcedWithoutActiveQuestionTurnsAnyContentPhraseIntoNewQuestion() {
        let plain = "основні ознаки держави"
        #expect(OwnerQuestionDetector.detectForced(text: plain, secondsSinceLastQuestion: nil, hasActiveQuestion: false)
                == .newQuestion(plain))
        let noMark = "розкажіть мені про принципи розділення влад у сучасній демократичній державі"   // без вопросительной формы
        #expect(OwnerQuestionDetector.detectForced(text: noMark, secondsSinceLastQuestion: nil, hasActiveQuestion: false)
                == .newQuestion(noMark))
    }

    @Test func forcedAcceptsLongRepeatedQuestionUpToFortyWords() {
        #expect(OwnerQuestionDetector.forcedMaxWords == 40 && OwnerQuestionDetector.maxWords == 15)
        let body = Array(repeating: "слово", count: 29).joined(separator: " ")
        let long = "Що таке держава і " + body + "?"                      // 33 слова: автоматический detect молчит
        #expect(OwnerQuestionDetector.detect(text: long, secondsSinceLastQuestion: 5, hasActiveQuestion: true) == .none)
        #expect(OwnerQuestionDetector.detectForced(text: long, secondsSinceLastQuestion: 5, hasActiveQuestion: true)
                == .replaceLastQuestion(long))
        #expect(OwnerQuestionDetector.detectForced(text: long, secondsSinceLastQuestion: nil, hasActiveQuestion: false)
                == .newQuestion(long))
        let exactly40 = Array(repeating: "слово", count: 40).joined(separator: " ")
        #expect(OwnerQuestionDetector.detectForced(text: exactly40, secondsSinceLastQuestion: 60, hasActiveQuestion: true)
                == .clarifyLastQuestion(correction: exactly40))
    }

    @Test func automaticDetectIsUnchangedByForcedWidening() {
        // D1: без взведённого режима детектор по-прежнему молчит на фразу без маркеров и на фразу длиннее 15 слов.
        #expect(OwnerQuestionDetector.detect(text: "основні ознаки держави", secondsSinceLastQuestion: nil, hasActiveQuestion: false) == .none)
        let sixteen = "Що таке держава " + Array(repeating: "слово", count: 13).joined(separator: " ")
        #expect(OwnerQuestionDetector.detect(text: sixteen, secondsSinceLastQuestion: 5, hasActiveQuestion: true) == .none)
    }

    @Test func hotkeyDefaults() {
        #expect(HotkeyBinding.defaults[.voiceClarify]?.displayString == "⌃⌥U")
        #expect(HotkeyBinding.sessionDefaults[.voiceClarify]?.displayString == "⇧⌘U")
        #expect(AppSettings().ownerVoiceClarification == false)    // D1 не тронут
    }
}
