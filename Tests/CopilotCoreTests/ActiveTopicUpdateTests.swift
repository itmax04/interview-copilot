import Testing
@testable import CopilotCore

/// COPILOT-17 R-05: Whisper уточняет корень билета. Данные синтетические.
@Suite struct ActiveTopicUpdateTests {
    private func ticket() -> (AnswerHistory, ActiveTopic?, root: Int, followUp: Int) {
        var h = AnswerHistory()
        let r = h.begin(question: "Назвіть сторони договору", turnID: 1, kind: .hint)
        var t: ActiveTopic? = ActiveTopic(rootExchangeID: 1, rootEntryID: r.entry, rootQuestion: "Назвіть сторони договору")
        let f = h.begin(question: "А винятки?", turnID: 2, kind: .hint, rootEntryID: r.entry, rootTitle: t?.rootTitle)
        t?.followUpDepth = 1
        return (h, t, r.entry, f.entry)
    }

    @Test func rootIsUpdatedEverywhere() {
        var (h, t, root, fu) = ticket()
        let out = TicketRootUpdate.apply(turn: 1, oldText: "Назвіть сторони договору", newText: "Назвіть сторони договору купівлі-продажу?",
                                         audioSeconds: 4, topic: &t, history: &h)
        #expect(out == .init(charsOld: 24, charsNew: 41))
        #expect(t?.rootQuestion == "Назвіть сторони договору купівлі-продажу?")
        #expect(t?.rootTitle == "Назвіть сторони договору купівлі-продажу?")
        #expect(h.entry(root)?.question == "Назвіть сторони договору купівлі-продажу?")
        #expect(h.entry(root)?.title == t?.rootTitle)
        #expect(h.entry(fu)?.rootTitle == t?.rootTitle)   // заголовок «К билету» в AnswerCardView берётся отсюда
        #expect(t?.followUpDepth == 1)
    }

    @Test func notUpdatedForNonRootTurn() {
        var (h, t, _, _) = ticket()
        #expect(TicketRootUpdate.apply(turn: 2, oldText: "А винятки?", newText: "А які винятки?", audioSeconds: 3, topic: &t, history: &h) == nil)
        #expect(t?.rootQuestion == "Назвіть сторони договору")
    }

    @Test func notUpdatedWhenTicketChanged() {
        var (h, t, _, _) = ticket()
        let r2 = h.begin(question: "Що таке позовна давність", turnID: 3, kind: .hint)
        t = ActiveTopic(rootExchangeID: 3, rootEntryID: r2.entry, rootQuestion: "Що таке позовна давність")
        #expect(TicketRootUpdate.apply(turn: 1, oldText: "Назвіть сторони договору", newText: "Інший текст вопроса", audioSeconds: 3, topic: &t, history: &h) == nil)
        #expect(t?.rootQuestion == "Що таке позовна давність")
        var none: ActiveTopic?
        #expect(TicketRootUpdate.apply(turn: 1, oldText: "Назвіть сторони договору", newText: "Інший", audioSeconds: 3, topic: &none, history: &h) == nil)
    }

    @Test func notUpdatedWhenRootTextDiffers() {
        var (h, t, _, _) = ticket()
        #expect(TicketRootUpdate.apply(turn: 1, oldText: "Зовсім інший текст", newText: "Назвіть сторони", audioSeconds: 3, topic: &t, history: &h) == nil)
    }

    @Test func notUpdatedForEmptyIdenticalOrHallucination() {
        var (h, t, _, _) = ticket()
        #expect(TicketRootUpdate.apply(turn: 1, oldText: "Назвіть сторони договору", newText: "  ", audioSeconds: 3, topic: &t, history: &h) == nil)
        #expect(TicketRootUpdate.apply(turn: 1, oldText: "Назвіть сторони договору", newText: "Назвіть сторони договору", audioSeconds: 3, topic: &t, history: &h) == nil)
        #expect(TicketRootUpdate.apply(turn: 1, oldText: "Назвіть сторони договору", newText: "Дякую за перегляд", audioSeconds: 1.5, topic: &t, history: &h) == nil)
        #expect(t?.rootRefined == false)
    }

    @Test func notUpdatedTwice() {
        var (h, t, _, _) = ticket()
        #expect(TicketRootUpdate.apply(turn: 1, oldText: "Назвіть сторони договору", newText: "Перший варіант тексту", audioSeconds: 3, topic: &t, history: &h) != nil)
        #expect(TicketRootUpdate.apply(turn: 1, oldText: "Перший варіант тексту", newText: "Другий варіант тексту", audioSeconds: 3, topic: &t, history: &h) == nil)
        #expect(t?.rootQuestion == "Перший варіант тексту")
    }
}
