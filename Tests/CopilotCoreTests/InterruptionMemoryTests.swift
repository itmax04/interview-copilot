import CopilotCore
import Testing

@Suite("Перебивание и короткие доп. вопросы — E-01")
struct InterruptionMemoryTests {
    @Test func interruptedOwnerAnswerAttachesToOriginalExchangeEvenAfterNewQuestion() {
        let mem = InterviewMemory()
        let firstID = mem.addQuestion("Розкажіть про позовну давність у ЦКУ.", turnID: 1)

        var assembler = OwnerAnswerAssembler(pauseMs: 1000)
        assembler.phraseFinal(text: "Загальний строк позовної давності становить три роки", utterance: 1, speechEnd: 2000, exchangeID: mem.currentExchangeID)

        // Экзаменатор перебил через 300 мс (пауза владельца ещё не дошла до 1000 мс).
        let flushed = assembler.flush()
        #expect(flushed?.targetExchangeID == firstID)

        // Даже если новый вопрос добавился раньше или позже — прерванный ответ крепится к firstID!
        let secondID = mem.addQuestion("А винятки?", turnID: 2)
        mem.addAnswer(flushed!.provisionalText, toExchangeID: flushed!.targetExchangeID)

        let exchanges = mem.all
        #expect(exchanges.count == 2)
        #expect(exchanges[0].id == firstID)
        #expect(exchanges[0].answer == ["Загальний строк позовної давності становить три роки"])
        #expect(exchanges[1].id == secondID)
        #expect(exchanges[1].answer.isEmpty)

        // Фоновое уточнение перераспознаванием обновляет именно первый обмен.
        mem.reviseAnswer("Загальний строк позовної давності становить три роки",
                         to: "Загальний строк позовної давності становить 3 роки.",
                         inExchangeID: firstID)
        #expect(mem.all[0].answer == ["Загальний строк позовної давності становить 3 роки."])
    }

    @Test func shortFollowUpsFireWhenActiveTopicEnabled() {
        var cfg = TurnDetector.Config(thresholdMs: 1000)
        cfg.allowShortFollowUps = true
        var d = TurnDetector(config: cfg)

        // Пустой бэкченнел (в том числе составной вроде «Добре, дякую.») не копится в pending.
        d.interviewerStartedSpeaking(at: 0)
        d.phraseFinal("Хорошо.", speechEnd: 400)
        #expect(d.pendingText.isEmpty)

        d.interviewerStartedSpeaking(at: 500)
        d.phraseFinal("Добре, дякую.", speechEnd: 900)
        #expect(d.pendingText.isEmpty)

        d.interviewerStartedSpeaking(at: 920)
        d.phraseFinal("Хорошо, спасибо.", speechEnd: 980)
        #expect(d.pendingText.isEmpty)

        // Короткий доп. вопрос из 2 слов проходит через полную паузу T (1000 мс).
        d.interviewerStartedSpeaking(at: 1000)
        d.interviewerStoppedSpeaking(at: 1600)
        d.phraseFinal("А винятки?", speechEnd: 1600)
        #expect(d.tick(at: 2200) == nil) // 600 мс мало — ждём полные 1000 мс
        let turn = d.tick(at: 2600)
        #expect(turn?.text == "А винятки?")

        // Однословный экзаменационный доп. вопрос без знака «?».
        d.interviewerStartedSpeaking(at: 3000)
        d.interviewerStoppedSpeaking(at: 3400)
        d.phraseFinal("Статья", speechEnd: 3400)
        let turn2 = d.tick(at: 4400)
        #expect(turn2?.text == "Статья")
    }

    @Test func bargeInOverlapDoesNotPermanentlySuppressExaminerQuestion() {
        var cfg = TurnDetector.Config(thresholdMs: 1000)
        cfg.allowShortFollowUps = true
        var d = TurnDetector(config: cfg)

        // Владелец отвечает с 0 мс.
        d.setOwnerSpeaking(true, at: 0)
        // Экзаменатор перебивает в 2000..2800 мс.
        d.interviewerStartedSpeaking(at: 2000)
        d.interviewerStoppedSpeaking(at: 2800)
        d.phraseFinal("Какая статья?", speechEnd: 2800)

        // Владелец договаривает хвост до 3100 мс: пока говорит — хода нет, но не глушится навсегда.
        #expect(d.tick(at: 3000) == nil)
        d.setOwnerSpeaking(false, at: 3100)

        // После того как владелец замолчал и прошла пауза T=1000 мс от speechEnd (3800 мс), ход срабатывает!
        let turn = d.tick(at: 3800)
        #expect(turn?.text == "Какая статья?")
    }
}
