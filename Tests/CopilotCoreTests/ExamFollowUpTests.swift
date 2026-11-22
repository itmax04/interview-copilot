import CopilotCore
import Testing

@Suite("Экзамен, активная тема, контекстный RAG и возврат к билету — E-02, E-04, E-05")
struct ExamFollowUpTests {
    @Test(arguments: [
        // UK exam follow-ups
        ("Яка стаття?", true),
        ("А винятки?", true),
        ("Які строки?", true),
        ("А наслідки?", true),
        ("У чому різниця?", true),
        ("А у цьому випадку?", true),
        ("Обґрунтуйте", true),
        ("Наведіть приклад", true),
        ("Що про це каже закон?", true),
        // RU exam follow-ups
        ("Какая статья?", true),
        ("А исключения?", true),
        ("Какие сроки?", true),
        ("А последствия?", true),
        ("В чём разница?", true),
        ("А если наоборот?", true),
        ("Конкретнее", true),
        // Topic shifts — NOT follow-ups
        ("Наступне питання про спадкування за заповітом.", false),
        ("Следующий вопрос: виды договоров.", false),
        ("Перейдём к теме залога.", false),
        ("Расскажите про договор аренды.", false),
    ])
    func examFollowUpDetector(question: String, expected: Bool) {
        #expect(FollowUpDetector.isFollowUp(question) == expected)
    }

    @Test func activeTopicBuildsContextualQueryAndKeepsRootMaterials() {
        let rootMat = MaterialHit(source: "ЦКУ_позовна_давність.md", text: "Ст. 257 ЦКУ: загальна позовна давність 3 роки.", score: 0.78)
        let topic = ActiveTopic(
            rootExchangeID: 1,
            rootEntryID: 10,
            rootQuestion: "Розкажіть про позовну давність у ЦКУ.",
            ownerLastSpoken: "Загальний строк становить три роки, але є спеціальні строки",
            lastShownHint: "Загальна позовна давність — 3 роки (ст. 257 ЦКУ).",
            rootMaterials: [rootMat]
        )

        let query = topic.contextualSearchQuery(for: "А винятки?")
        #expect(query.contains("позовну давність"))
        #expect(query.contains("спеціальні строки"))
        #expect(query.contains("А винятки?"))

        let sameDocHit = MaterialHit(source: "ЦКУ_позовна_давність.md", text: "Ст. 268 ЦКУ: вимоги, на які позовна давність не поширюється.", score: 0.46)
        let weakOffTopic = MaterialHit(source: "Трудовий_кодекс.md", text: "Винятки щодо понаднормової роботи.", score: 0.44)
        let strongOffTopic = MaterialHit(source: "Судова_практика.md", text: "Велика Палата щодо винятків позовної давності.", score: 0.65)

        let merged = topic.mergeMaterials(followUpHits: [weakOffTopic, sameDocHit, strongOffTopic])
        #expect(merged.first?.source == "ЦКУ_позовна_давність.md")
        #expect(merged.contains { $0.source == "Судова_практика.md" })
        #expect(!merged.contains { $0.source == "Трудовий_кодекс.md" })
        #expect(merged.contains { $0.text.contains("Ст. 257") })
    }

    @Test func transcriptSanityCheckDetectsGarbledFragments() {
        #expect(TranscriptSanityCheck.looksUnclear("") == true)
        #expect(TranscriptSanityCheck.looksUnclear("эм ну") == true)
        #expect(TranscriptSanityCheck.looksUnclear("абвгджзклмн") == true)
        #expect(TranscriptSanityCheck.looksUnclear("текст \u{FFFD} обрыв") == true)

        // Валидные короткие доп. вопросы не помечаются как мусор.
        #expect(TranscriptSanityCheck.looksUnclear("А винятки?") == false)
        #expect(TranscriptSanityCheck.looksUnclear("Статья") == false)
        #expect(TranscriptSanityCheck.looksUnclear("Які строки позовної давності?") == false)
    }

    @Test func examPromptEnforcesNoFabricationActiveTopicAndUnderstoodReminder() {
        let topic = ActiveTopic(
            rootExchangeID: 1,
            rootEntryID: 1,
            rootQuestion: "Позовна давність у ЦКУ",
            ownerLastSpoken: "Я сказав про загальний строк 3 роки",
            lastShownHint: "Ст. 257 ЦКУ — 3 роки."
        )
        let ctx = FollowUpContext(isFollowUp: true, activeTopic: topic, transcriptUnclear: true)
        let req = PromptBuilder.hintRequest(
            question: "бвгджзклмн",
            transcript: [],
            cards: [],
            baseCard: nil,
            profile: nil,
            redactPII: false,
            answerLanguage: "uk",
            session: SessionPrompt(type: .exam),
            followUp: ctx
        )

        #expect(req.system.contains("NEVER fabricate or guess specific article numbers"))
        #expect(!req.system.contains("improvise freely"))
        let user = req.messages[0].text
        #expect(user.contains("<active_topic>"))
        #expect(user.contains("Я сказав про загальний строк 3 роки"))
        #expect(user.contains("<stt_warning>"))
        #expect(user.contains("Format reminder: start line 1 with \"❓ \""))
        #expect(user.contains("strictly in Ukrainian only"))
    }

    @Test func answerHistoryLinksFollowUpsToRootTicketForOneClickReturn() {
        var history = AnswerHistory()
        let root = history.begin(question: "Розкажіть про позовну давність у ЦКУ.", turnID: 1, kind: .hint)
        let rootTitle = history.entry(root.entry)!.title

        let fu1 = history.begin(question: "А винятки?", turnID: 2, kind: .hint, rootEntryID: root.entry, rootTitle: rootTitle)
        let fu2 = history.begin(question: "А яка стаття?", turnID: 3, kind: .hint, rootEntryID: root.entry, rootTitle: rootTitle)

        #expect(history.current?.id == fu2.entry)
        #expect(history.current?.rootEntryID == root.entry)
        #expect(history.entry(fu1.entry)?.rootTitle == rootTitle)

        // Возврат к основному билету в 1 клик с 3-й карточки.
        history.select(entry: root.entry)
        #expect(history.current?.id == root.entry)
    }
}
