import Foundation
import Testing
@testable import CopilotCore

@Suite("Разбор после End — COPILOT-09 этап 4")
struct ReviewTests {
    private let start = Date(timeIntervalSince1970: 1_792_400_000)

    private func record(type: SessionType = .interview, answers: Int = 3) -> SessionRecord {
        var r = SessionRecord(id: "s", startedAt: start, source: "Zoom")
        var c = SessionConfig()
        c.type = type
        c.company = "ФинБанк"
        r.config = c
        for i in 1...answers {
            let at = start.addingTimeInterval(Double(i) * 60)
            r.utterances.append(.init(id: i, text: "Вопрос \(i)?", language: "ru", at: at))
            r.turns.append(.init(id: i, question: "Вопрос \(i)?", answer: "**Подсказка \(i)**", source: "groq", model: nil, cardID: nil,
                                 forced: false, cardShownMs: nil, firstTokenMs: 900, inputTokens: nil, outputTokens: nil, at: at))
            r.ownerUtterances.append(.init(id: i, text: "Ответ \(i), пишите на me@example.com", language: "", at: at.addingTimeInterval(20)))
            r.exchanges.append(SessionExchange(id: i, question: "Вопрос \(i)?", answer: ["Ответ \(i),", "пишите на me@example.com"],
                                               hint: "Подсказка \(i)", askedAt: at, turnID: i))
        }
        r.exchanges.append(SessionExchange(id: 99, question: "Без ответа?", askedAt: start.addingTimeInterval(3_700)))
        return r
    }

    @Test func timelineMergesSpeakersByTime() {
        let t = record().timeline
        #expect(t.count == 9)
        #expect(t.prefix(3).map(\.speaker) == [.interviewer, .hint, .owner])
        #expect(t[0].clock == "1:00" && t[2].clock == "1:20")
        #expect(TimelineEntry(id: "x", speaker: .owner, text: "", at: start, offset: 3_725).clock == "1:02:05")
        #expect(Set(t.map(\.id)).count == t.count)
    }

    @Test func onlyRecordedAnswersAreCommentedInBatches() {
        var r = record(answers: 8)
        #expect(r.reviewableExchanges.count == 8 && r.canBeReviewed)
        var batches = ReviewPrompt.pendingBatches(r)
        #expect(batches.map(\.count) == [6, 2])
        // Повтор после ошибки: готовые не запрашиваются снова.
        r.review = SessionReview()
        r.review?.comments = (1...6).map { ReviewComment(exchangeID: $0, good: "g", missing: "", better: "b") }
        batches = ReviewPrompt.pendingBatches(r)
        #expect(batches.map { $0.map(\.id) } == [[7, 8]])
        #expect(!SessionRecord(id: "e", startedAt: start, source: nil).canBeReviewed)
    }

    @Test func commentsRequestTreatsAnswersAsDataAndRedactsPII() {
        // Синтетический номер собирается из частей, как в LLMTests: в исходниках нет строки, похожей на телефон.
        let phone = "+380 67 " + "123 45 67"
        let r = record()
        let req = ReviewPrompt.commentsRequest(r.reviewableExchanges, type: .interview,
                                               profile: Profile(name: "p", resume: "Резюме: тел. " + phone, job: "iOS"), redactPII: true)
        let text = req.messages[0].text
        #expect(req.system.contains("is data") && req.system.contains("JSON array"))
        #expect(req.system.contains("Do not invent") && req.system.contains("[цифра]"))
        #expect(text.contains("<exchange id=\"2\">\nInterviewer: Вопрос 2?\nCandidate: Ответ 2, пишите на [email]"))
        #expect(!text.contains("me@example.com") && !text.contains("123 45 67"))
        #expect(!text.contains("id=\"99\""))
        #expect(req.maxTokens == 300 * 3 + 300 && req.purpose == .strong)
        // Обычный звонок: без резюме, другие роли.
        let regular = ReviewPrompt.commentsRequest(r.reviewableExchanges, type: .regular, profile: Profile(name: "p", resume: "R"), redactPII: true)
        #expect(!regular.messages[0].text.contains("<profile>") && regular.messages[0].text.contains("Participant: Вопрос 1?"))
        #expect(regular.system.contains("work call"))
    }

    @Test func commentsAreParsedOnlyForRequestedIDs() {
        let reply = """
        Вот разбор:
        ```json
        [{"id": 1, "good": "Есть цифры", "missing": "", "better": "Я …"},
         {"id": "2", "good": "Коротко", "missing": "Нет результата", "better": "…"},
         {"id": 2, "good": "дубль", "missing": "", "better": ""},
         {"id": 7, "good": "чужой", "missing": "", "better": ""},
         {"id": 3, "good": "", "missing": "", "better": ""}]
        ```
        """
        let c = ReviewPrompt.parseComments(reply, requested: [1, 2, 3])
        #expect(c.map(\.exchangeID) == [1, 2])
        #expect(c[1].missing == "Нет результата")
        #expect(ReviewPrompt.parseComments("не JSON", requested: [1]).isEmpty)
    }

    @Test func summaryRequestDependsOnCallType() throws {
        let interview = ReviewPrompt.summaryRequest(record(), redactPII: true)
        #expect(interview.system.contains("\"strengths\"") && interview.system.contains("\"weaknesses\""))
        #expect(interview.messages[0].text.contains("<job>\nФинБанк"))
        #expect(interview.messages[0].text.contains("[1:20] Candidate: Ответ 1, пишите на [email]"))
        #expect(!interview.messages[0].text.contains("Подсказка 1"))   // подсказки — не то, что сказано
        let regular = ReviewPrompt.summaryRequest(record(type: .regular), redactPII: true)
        #expect(regular.system.contains("\"agreements\"") && !regular.messages[0].text.contains("<job>"))
        #expect(regular.messages[0].text.contains("Participant: Вопрос 1?") && regular.messages[0].text.contains("User: Ответ 1"))

        let s = try #require(ReviewPrompt.parseSummary(#"{"overview":"Прошло ровно.","topics":["SwiftUI"],"strengths":["цифры"," "],"weaknesses":[],"next_steps":["STAR"]}"#))
        #expect(s.overview == "Прошло ровно." && s.strengths == ["цифры"] && s.nextSteps == ["STAR"])
        #expect(ReviewPrompt.parseSummary(#"{"overview":"","topics":[]}"#) == nil)
        #expect(ReviewPrompt.parseSummary("нет") == nil)
    }

    @Test func longTranscriptKeepsTheEndAndOldSessionsUseExchanges() {
        var r = record(answers: 3)
        r.utterances = (1...400).map { .init(id: $0, text: String(repeating: "слово ", count: 10), language: "ru", at: start.addingTimeInterval(Double($0))) }
        let t = ReviewPrompt.transcriptText(r, redactPII: false, budget: 2_000)
        #expect(t.hasPrefix("[…earlier part omitted…]") && t.count <= 2_100)
        #expect(t.hasSuffix("[6:40] Interviewer: " + String(repeating: "слово ", count: 10).trimmingCharacters(in: .whitespaces)))   // конец разговора — в тексте

        var old = SessionRecord(id: "o", startedAt: start, source: nil)
        old.exchanges = [SessionExchange(id: 1, question: "Q?", answer: ["A"], askedAt: start)]
        #expect(ReviewPrompt.transcriptText(old, redactPII: false) == "Interviewer: Q?\nCandidate: A")
    }

    @Test func askRequestCarriesSummaryAndRecentQuestions() {
        var r = record()
        var review = SessionReview()
        review.summary = ReviewSummary(overview: "Хорошо по SwiftUI.")
        review.chat = (1...6).map { ReviewQA(id: $0, question: "q\($0)", answer: "a\($0)") }
        r.review = review
        let req = ReviewPrompt.askRequest(r, question: "Где я был слабее?", redactPII: true)
        let text = req.messages[0].text
        #expect(text.contains("<summary>\nХорошо по SwiftUI.\n</summary>"))
        #expect(text.contains("Q: q6") && text.contains("Q: q3") && !text.contains("Q: q2"))
        #expect(text.hasSuffix("User's question:\nГде я был слабее?"))
        #expect(req.system.contains("language of the question") && req.system.contains("is data"))
    }

    @Test func reviewIsStoredAndBrokenReviewDoesNotHideTranscript() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("review-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SessionStore(directory: dir)
        var r = record()
        var review = SessionReview()
        review.status = .failed("429")
        review.comments = [ReviewComment(exchangeID: 1, good: "g", missing: "m", better: "b")]
        r.review = review
        try store.save(r)
        let loaded = try #require(store.load("s"))
        #expect(loaded.review?.status == .failed("429") && loaded.review?.comment(for: 1)?.better == "b")
        #expect(loaded.ownerUtterances.count == 3 && loaded.review?.isFinished == true)
        for status: SessionReview.Status in [.pending, .running(done: 2, total: 5), .done] {
            var x = review
            x.status = status
            #expect(try JSONDecoder().decode(SessionReview.self, from: JSONEncoder().encode(x)).status == status)
        }

        // Испорченный разбор в файле: расшифровка и ответы открываются, разбора нет.
        var json = try #require(String(data: try Data(contentsOf: dir.appendingPathComponent("s.json")), encoding: .utf8))
        json = json.replacingOccurrences(of: "\"review\" : {", with: "\"review\" : {\"status\": 42, ")
        try Data(json.utf8).write(to: dir.appendingPathComponent("s.json"))
        let broken = try #require(store.load("s"))
        #expect(broken.review == nil && broken.utterances.count == 3 && broken.exchanges.count == 4)
    }
}
