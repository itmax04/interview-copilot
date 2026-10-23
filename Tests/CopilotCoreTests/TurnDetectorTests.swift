import Foundation
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
        d.phraseFinal("Расскажите о себе, пожалуйста.", speechEnd: 2000)
        #expect(d.tick(at: 2600) == nil)
        let turn = run(&d, from: 2600, until: 5000)
        #expect(turn?.text == "Расскажите о себе, пожалуйста.")
        #expect(turn?.firedAt == 2700)
        #expect(turn?.speechEndedAt == 2000)
        #expect(turn?.forced == false)
    }

    @Test func questionMarkShortensPause() {
        // COPILOT-04 R-02: «?» в конце — ждём 350 мс вместо T.
        var d = TurnDetector()
        d.interviewerStartedSpeaking(at: 0)
        d.interviewerStoppedSpeaking(at: 2000)
        d.phraseFinal("Почему вы уходите с текущего места?", speechEnd: 2000)
        #expect(d.tick(at: 2300) == nil)
        #expect(run(&d, from: 2350, until: 5000)?.firedAt == 2350)
    }

    @Test func questionPauseNeverExceedsT() {
        var config = TurnDetector.Config(thresholdMs: 400)
        config.questionThresholdMs = 900
        var d = TurnDetector(config: config)
        d.interviewerStartedSpeaking(at: 0)
        d.phraseFinal("What is the difference between them?", speechEnd: 1000)
        #expect(run(&d, from: 1000, until: 3000)?.firedAt == 1400)
    }

    @Test func questionStartersAreOffByDefault() {
        var d = TurnDetector()
        d.phraseFinal("Как вы организуете работу команды.", speechEnd: 1000)
        #expect(d.waitMs(for: d.pendingText) == 700)
        d.config.questionStarters = true
        #expect(d.waitMs(for: d.pendingText) == 350)
    }

    @Test func draftIsReadyBeforeTheTurn() {
        // COPILOT-04 R-01: текст для опережающего запроса — сразу по итогу, до истечения T.
        var d = TurnDetector()
        d.interviewerStartedSpeaking(at: 0)
        d.interviewerStoppedSpeaking(at: 2000)
        #expect(d.draft(at: 2100) == nil)                 // итог ещё не пришёл
        d.phraseFinal("Расскажите о своём последнем проекте.", speechEnd: 2000)
        #expect(d.draft(at: 2500) == "Расскажите о своём последнем проекте.")
        #expect(d.tick(at: 2500) == nil)                  // ход — позже
        d.interviewerStartedSpeaking(at: 2600)
        #expect(d.draft(at: 2650) == nil)                 // собеседник продолжил
    }

    @Test func noDraftForUnfinishedShortOrOwner() {
        var d = TurnDetector()
        d.phraseFinal("Расскажите о проекте, который", speechEnd: 1000)
        #expect(d.draft(at: 1500) == nil)                 // оборвано
        var short = TurnDetector()
        short.phraseFinal("Угу, так.", speechEnd: 1000)
        #expect(short.draft(at: 1500) == nil)             // < 3 слов
        var owner = TurnDetector()
        owner.phraseFinal("Какие у вас вопросы к нам?", speechEnd: 1000)
        owner.setOwnerSpeaking(true, at: 1300)
        #expect(owner.draft(at: 1500) == nil)             // владелец отвечает сам (S-07)
    }

    @Test func evalCountsDraftsAndWastedRequests() throws {
        // COPILOT-04 R-04: eval `turn` показывает, когда стартует опережающий запрос и сколько запросов лишние.
        let lines = [
            #"{"id":"q","segments":[["Почему вы уходите с текущего места?",0,2000]],"expected_turn_at":2000}"#,
            #"{"id":"gap","segments":[["Расскажите о вашем опыте.",0,1500],["Особенно в больших командах.",2100,3800]],"expected_turn_at":3800}"#,
        ]
        let cases = try lines.map { try JSONDecoder().decode(TurnEval.Case.self, from: Data($0.utf8)) }
        let summary = TurnEval.run(cases)
        #expect(summary.premature == 0 && summary.missed == 0)
        #expect(summary.draftHits == 2)
        #expect(summary.meanDraftLatencyMs == 500)   // итог Parakeet через 500 мс после конца речи
        #expect(summary.draftWasted == 1)            // первая фраза gap-случая ходом не стала
        #expect(summary.results.first?.firedAt == 2500)
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
        // Вопрос со знаком «?» — пауза 350 мс (COPILOT-04 R-02); эхо ход не блокирует.
        #expect(run(&d, from: 2500, until: 5000)?.firedAt == 2850)
    }

    @Test func echoDetectedByMicFirstIsIgnored() {
        // Микрофон услышал динамики на 200 мс раньше, чем VAD захвата.
        var d = TurnDetector()
        d.setOwnerSpeaking(true, at: 800)
        d.interviewerStartedSpeaking(at: 1000)
        d.interviewerStoppedSpeaking(at: 3000)
        d.phraseFinal("Tell me about yourself and your background.", speechEnd: 3000)
        #expect(run(&d, from: 3000, until: 5000)?.firedAt == 3700)
    }

    @Test func realOwnerSpeechBeforeQuestionStillCounts() {
        // Владелец говорил задолго до вопроса и продолжает — это не эхо.
        var d = TurnDetector()
        d.setOwnerSpeaking(true, at: 0)
        d.interviewerStartedSpeaking(at: 2000)
        d.interviewerStoppedSpeaking(at: 4000)
        d.phraseFinal("Could you repeat your last point please?", speechEnd: 4000)
        #expect(run(&d, from: 4000, until: 6000) == nil)
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

    @Test func resetClearsStaleState() {
        // Ревью P-13: после паузы владелец «не говорит», а ⌃⌥↩ не ждёт старой фразы.
        var d = TurnDetector()
        d.interviewerStartedSpeaking(at: 0)
        d.interviewerStoppedSpeaking(at: 1000)
        d.setOwnerSpeaking(true, at: 2000)
        d.reset()
        #expect(d.force(at: 3000) == nil) // нет текста и не ждём итог старой фразы
        d.interviewerStartedSpeaking(at: 4000)
        d.interviewerStoppedSpeaking(at: 6000)
        d.phraseFinal("Tell me about your strengths.", speechEnd: 6000)
        #expect(run(&d, from: 6000, until: 8000)?.forced == false) // автоответ не подавлен
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
