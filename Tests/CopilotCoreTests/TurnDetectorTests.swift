import Testing
@testable import CopilotCore

@Suite("TurnDetector — R-05, S-07")
struct TurnDetectorTests {
    /// Прогон по времени шагами 50 мс до `until`; возвращает первый ход.
    func run(_ d: inout TurnDetector, from: Double, until: Double) -> Turn? {
        var t = from
        while t <= until {
            if let turn = d.tick(at: t) { return turn }
            t += 50
        }
        return nil
    }

    @Test func completedQuestionFiresAfterThreshold() {
        var d = TurnDetector()
        d.interviewerStartedSpeaking(at: 0)
        d.interviewerStoppedSpeaking(at: 2000)
        d.phraseFinal("Расскажите о себе, пожалуйста?", speechEnd: 2000)
        #expect(d.tick(at: 2600) == nil)
        let turn = run(&d, from: 2600, until: 5000)
        #expect(turn?.text == "Расскажите о себе, пожалуйста?")
        #expect(turn?.firedAt == 2700)
        #expect(turn?.speechEndedAt == 2000)
        #expect(turn?.forced == false)
    }

    @Test func shortRepliesAreNotTurns() {
        var d = TurnDetector()
        d.interviewerStartedSpeaking(at: 0)
        d.phraseFinal("Угу, так.", speechEnd: 500)
        #expect(run(&d, from: 500, until: 4000) == nil)
    }

    @Test func pauseMidSentenceWaitsLonger() {
        var d = TurnDetector()
        d.interviewerStartedSpeaking(at: 0)
        d.phraseFinal("Расскажите о проекте, который", speechEnd: 1500)
        // Через T=700 мс хода нет: фраза оборвана на «который».
        #expect(run(&d, from: 1500, until: 2600) == nil)
        d.interviewerStartedSpeaking(at: 2700)
        d.phraseFinal("вы сделали в прошлом году.", speechEnd: 4000)
        let turn = run(&d, from: 4000, until: 6000)
        #expect(turn?.text == "Расскажите о проекте, который вы сделали в прошлом году.")
        #expect(turn?.firedAt == 4700)
    }

    @Test func waitsForFinalOfSecondPhrase() {
        // Регрессия (eval turn): вторая фраза закончилась, её текст ещё не пришёл — нельзя отдавать вопрос без неё.
        var d = TurnDetector()
        d.interviewerStartedSpeaking(at: 0)
        d.interviewerStoppedSpeaking(at: 1600)
        d.phraseFinal("Расскажите о проекте, который", speechEnd: 1600)
        d.interviewerStartedSpeaking(at: 2600)
        d.interviewerStoppedSpeaking(at: 4200)
        #expect(run(&d, from: 4200, until: 4650) == nil)
        d.phraseFinal("вы сделали в прошлом году.", speechEnd: 4200)
        let turn = run(&d, from: 4700, until: 6000)
        #expect(turn?.text == "Расскажите о проекте, который вы сделали в прошлом году.")
        #expect(turn?.firedAt == 4900)
    }

    @Test func multiPhraseQuestionAccumulates() {
        var d = TurnDetector()
        d.interviewerStartedSpeaking(at: 0)
        d.phraseFinal("Хорошо.", speechEnd: 600)
        d.interviewerStartedSpeaking(at: 900) // пауза 300 мс < T
        d.phraseFinal("Tell me about a conflict in your team.", speechEnd: 3000)
        #expect(run(&d, from: 600, until: 5000)?.text == "Хорошо. Tell me about a conflict in your team.")
    }

    @Test func ownerSpeakingBlocksAutoTurn() {
        var d = TurnDetector()
        d.interviewerStartedSpeaking(at: 0)
        d.interviewerStoppedSpeaking(at: 2000)
        d.phraseFinal("Why do you want to join us?", speechEnd: 2000)
        d.setOwnerSpeaking(true, at: 2500)
        #expect(run(&d, from: 2000, until: 6000) == nil)
        d.setOwnerSpeaking(false, at: 4000)
        #expect(run(&d, from: 4000, until: 7000) == nil)
        // ⌃⌥↩ работает всегда (S-07).
        let forced = d.force(at: 7000)
        #expect(forced?.text == "Why do you want to join us?")
        #expect(forced?.forced == true)
    }

    @Test func echoWhileInterviewerSpeaksIsIgnored() {
        var d = TurnDetector()
        d.interviewerStartedSpeaking(at: 0)
        d.phraseFinal("Хорошо.", speechEnd: 500)
        d.interviewerStartedSpeaking(at: 800)
        d.setOwnerSpeaking(true, at: 900)   // динамики → микрофон
        d.interviewerStoppedSpeaking(at: 2500)
        d.setOwnerSpeaking(false, at: 2800)
        d.phraseFinal("Как вы решаете конфликты в команде?", speechEnd: 2500)
        #expect(run(&d, from: 2500, until: 5000)?.firedAt == 3200)
    }

    @Test func echoTailRightAfterStopIsIgnored() {
        var d = TurnDetector()
        d.interviewerStartedSpeaking(at: 0)
        d.interviewerStoppedSpeaking(at: 2000)
        d.setOwnerSpeaking(true, at: 2200) // хвост эха в пределах 400 мс
        d.setOwnerSpeaking(false, at: 2300)
        d.phraseFinal("What is your biggest weakness?", speechEnd: 2000)
        #expect(run(&d, from: 2000, until: 4000) != nil)
    }

    @Test func forceWithoutPendingUsesLastPhrase() {
        var d = TurnDetector()
        d.interviewerStartedSpeaking(at: 0)
        d.phraseFinal("Опишіть свій найскладніший проєкт.", speechEnd: 1000)
        let first = run(&d, from: 1000, until: 3000)
        #expect(first != nil)
        #expect(d.force(at: 5000)?.text == "Опишіть свій найскладніший проєкт.")
        var empty = TurnDetector()
        #expect(empty.force(at: 0) == nil)
    }

    @Test func newSpeechCancelsPendingDecision() {
        var d = TurnDetector()
        d.interviewerStartedSpeaking(at: 0)
        d.phraseFinal("Tell me about yourself.", speechEnd: 1000)
        d.interviewerStartedSpeaking(at: 1500)
        #expect(run(&d, from: 1500, until: 4000) == nil) // всё ещё говорит
    }

    @Test func unfinishedHeuristics() {
        #expect(TurnDetector.looksUnfinished("Tell me about the project which"))
        #expect(TurnDetector.looksUnfinished("Розкажіть про проєкт, що"))
        #expect(TurnDetector.looksUnfinished("Расскажите,"))
        #expect(!TurnDetector.looksUnfinished("Расскажите о себе."))
        #expect(!TurnDetector.looksUnfinished("Why?"))
        #expect(TurnDetector.wordCount("Ну, э — так") == 3)
    }
}
