import Foundation
import Testing
@testable import CopilotCore

@Suite("Состояния сессии и распознавания вопроса — COPILOT-09 AC-01, AC-04, AC-05")
struct SessionStateTests {
    @Test func detectionFollowsEventsOfOneQuestion() {
        // Собеседник договорил → опережающий запрос → ход → снова заговорил.
        var d = QuestionDetection.idle
        d = d.next(on: .draftReady)
        #expect(d == .checking)
        d = d.next(on: .turnCompleted)
        #expect(d == .detected)
        d = d.next(on: .speechStarted)
        #expect(d == .idle)
        // Реплика оказалась не вопросом.
        d = d.next(on: .draftReady).next(on: .turnCompleted).next(on: .notAQuestion)
        #expect(d == .notQuestion)
        // Clear, начало и конец сессии — с чистого листа.
        #expect(d.next(on: .reset) == .idle)
        #expect(QuestionDetection.checking.next(on: .reset) == .idle)
    }

    @Test func pillShowsPreparingWhileAnswerHasNoTextYet() {
        #expect(QuestionDetection.idle.display(answerWaiting: false) == .hidden)
        #expect(QuestionDetection.checking.display(answerWaiting: false) == .checking)
        #expect(QuestionDetection.detected.display(answerWaiting: false) == .detected)
        #expect(QuestionDetection.notQuestion.display(answerWaiting: false) == .notQuestion)
        // Вопрос найден, запрос ушел, текста нет — «Готовлю ответ…», а не «Вопрос найден».
        #expect(QuestionDetection.detected.display(answerWaiting: true) == .preparing)
        #expect(QuestionDetection.idle.display(answerWaiting: true) == .preparing)
    }

    @Test func startAndEndAreIdempotent() {
        #expect(SessionPhase.none.canStart && !SessionPhase.none.canEnd)
        #expect(!SessionPhase.active.canStart && SessionPhase.active.canEnd)
        #expect(!SessionPhase.starting.canStart && !SessionPhase.starting.canEnd)
        #expect(!SessionPhase.ending.canStart && !SessionPhase.ending.canEnd)
        // После ошибки можно начать заново; завершать нечего.
        let failed = SessionPhase.failed("нет разрешения")
        #expect(failed.isFailed && failed.canStart && !failed.canEnd)
        #expect(!SessionPhase.active.isFailed)
    }

    @Test func chatNotesExtendSessionInstructionsAndReachThePrompt() {
        var c = SessionConfig()
        c.instructions = "Акцент на руководстве командой"
        let withNotes = c.withSessionNotes(["Отвечай по-английски", "  ", "Без Kafka"])
        #expect(withNotes.instructions == "Акцент на руководстве командой\nОтвечай по-английски\nБез Kafka")
        #expect(c.withSessionNotes([]).instructions == c.instructions)
        var empty = SessionConfig()
        empty.instructions = ""
        #expect(empty.withSessionNotes(["Коротко"]).instructions == "Коротко")
        // Указание попадает в блок <this_session> системной части.
        let system = PromptBuilder.system(profile: PromptScenarios.sampleProfile, redactPII: true,
                                          session: SessionPrompt(type: .interview, instructions: withNotes.instructions))
        #expect(system.contains("<this_session>\nАкцент на руководстве командой\nОтвечай по-английски\nБез Kafka\n</this_session>"))
    }
}
