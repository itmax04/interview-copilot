import Foundation
import Testing
@testable import CopilotCore

@Suite("QuestionBank — R-06, S-10")
struct QuestionBankTests {
    static let exampleURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../profile.example").standardized

    @Test func exampleBankIsValid() throws {
        let cards = try QuestionBankParser.load(Self.exampleURL.appendingPathComponent("questions.yaml"))
        #expect(cards.count >= 15)
        #expect(Set(cards.map(\.id)).count == cards.count)
        #expect(cards.contains { $0.isSTAR })
        // На трёх языках: в каждой карточке есть кириллица и латиница, а в базе — украинские буквы.
        let all = cards.flatMap(\.questions).joined()
        #expect(all.contains("і") && all.contains("ы") && all.contains("you"))
    }

    @Test func parsesFields() throws {
        let yaml = """
        - id: about-me
          questions: [ "Расскажите о себе", "Tell me about yourself" ]
          answer: |
            • пункт
          tags: [STAR]
        - id: single
          questions: "Один вопрос"
          answer: Ответ
        """
        let cards = try QuestionBankParser.parse(yaml)
        #expect(cards == [
            BankCard(id: "about-me", questions: ["Расскажите о себе", "Tell me about yourself"], answer: "• пункт", tags: ["STAR"]),
            BankCard(id: "single", questions: ["Один вопрос"], answer: "Ответ"),
        ])
        #expect(cards[0].isSTAR)
    }

    @Test func duplicateIdReportsLine() {
        let yaml = """
        - id: a
          questions: [q]
          answer: x
        - id: a
          questions: [q2]
          answer: y
        """
        #expect(throws: QuestionBankError(line: 4, message: "повтор id «a» (первое в строке 1)")) {
            try QuestionBankParser.parse(yaml)
        }
    }

    @Test(arguments: [
        ("- id: Bad_Id\n  questions: [q]\n  answer: x", 1),
        ("- id: ok\n  questions: []\n  answer: x", 1),
        ("- questions: [q]\n  answer: x", 1),
        ("- id: a\n  questions: [q]\n  answer: x\n- id: b\n  answer: y", 4),
    ])
    func validationErrors(yaml: String, line: Int) {
        do {
            _ = try QuestionBankParser.parse(yaml)
            Issue.record("ожидалась ошибка")
        } catch let error as QuestionBankError {
            #expect(error.line == line)
            #expect(error.description.hasPrefix("Question bank: ошибка в строке \(line)"))
        } catch {
            Issue.record("неожиданная ошибка \(error)")
        }
    }

    @Test func syntaxErrorHasLine() {
        let yaml = "- id: a\n  questions: [q\n  answer: x\n"
        do {
            _ = try QuestionBankParser.parse(yaml)
            Issue.record("ожидалась ошибка")
        } catch let error as QuestionBankError {
            #expect(error.line != nil)
        } catch {
            Issue.record("неожиданная ошибка \(error)")
        }
    }

    @Test func notAListIsError() {
        #expect(throws: QuestionBankError.self) { try QuestionBankParser.parse("id: a\nanswer: b") }
    }

    @Test func exampleProfileLoads() {
        let profile = ProfileStore.load(from: Self.exampleURL)
        #expect(profile.name == "Senior iOS Developer")
        #expect(profile.resume.contains("Senior iOS"))
        #expect(profile.instructions.isEmpty)
    }

    @Test func fileWatcherSeesAtomicSave() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("watch-\(UUID().uuidString).yaml")
        try "a".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let sink = EventSink()
        let watcher = FileWatcher(url: url) { sink.add(.speechStarted(utterance: 0)) }
        watcher.start()
        try await Task.sleep(for: .milliseconds(200))
        try "b".write(to: url, atomically: true, encoding: .utf8) // замена файла, как в редакторах
        #expect(await sink.waitFor { !$0.isEmpty })
        watcher.stop()
    }
}

/// Детерминированный эмбеддер: вектор — «мешок» символьных биграмм (для проверки логики без модели).
final class StubEmbedder: TextEmbedder, @unchecked Sendable {
    let identifier = "stub"
    private(set) var calls = 0

    func embed(_ texts: [String]) throws -> [[Float]] {
        calls += texts.count
        return texts.map { text in
            var v = [Float](repeating: 0, count: 64)
            let chars = Array(text.lowercased().filter { $0.isLetter })
            for i in 0..<max(0, chars.count - 1) {
                var h = Hasher()
                h.combine(chars[i]); h.combine(chars[i + 1])
                v[abs(h.finalize()) % 64] += 1
            }
            return v.normalized()
        }
    }
}

@Suite("BankMatcher — R-07")
struct BankMatcherTests {
    let cards = [
        BankCard(id: "about-me", questions: ["Расскажите о себе", "Tell me about yourself"], answer: "a"),
        BankCard(id: "salary", questions: ["Какие у вас зарплатные ожидания?"], answer: "b"),
        BankCard(id: "weakness", questions: ["Какие у вас слабые стороны?"], answer: "c"),
        BankCard(id: "five-years", questions: ["Где вы видите себя через пять лет?"], answer: "d"),
    ]

    @Test func exactQuestionMatches() throws {
        let builder = BankIndexBuilder(embedder: StubEmbedder(), cacheDirectory: nil)
        let index = try builder.build(cards)
        let m = index.match(try builder.embedQuery("Tell me about yourself"), threshold: 0.85)
        #expect(m.matched?.card.id == "about-me")
        #expect(abs((m.matched?.score ?? 0) - 1) < 0.0001)
        #expect(m.top.count == 3)
        #expect(m.top.map(\.score) == m.top.map(\.score).sorted(by: >))
    }

    @Test func belowThresholdGivesTop3Only() throws {
        let builder = BankIndexBuilder(embedder: StubEmbedder(), cacheDirectory: nil)
        let index = try builder.build(cards)
        let m = index.match(try builder.embedQuery("Как работает async/await?"), threshold: 0.99)
        #expect(m.matched == nil)
        #expect(m.top.count == 3)
    }

    @Test func maxOverQuestionsPerCard() throws {
        let builder = BankIndexBuilder(embedder: StubEmbedder(), cacheDirectory: nil)
        let index = try builder.build(cards)
        let m = index.match(try builder.embedQuery("Расскажите о себе"), threshold: 0.5)
        #expect(m.top.filter { $0.card.id == "about-me" }.count == 1)
    }

    @Test func cacheAvoidsRecomputation() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = StubEmbedder()
        _ = try BankIndexBuilder(embedder: first, cacheDirectory: dir).build(cards)
        #expect(first.calls == 5)
        // Новый процесс: всё из кэша, кроме новой формулировки.
        let second = StubEmbedder()
        var changed = cards
        changed[1].questions.append("Сколько вы хотите получать?")
        _ = try BankIndexBuilder(embedder: second, cacheDirectory: dir).build(changed)
        #expect(second.calls == 1)
    }
}

@Suite("RecognitionVocabulary — подсказка распознаванию")
struct RecognitionVocabularyTests {
    let cards = [
        BankCard(id: "a", questions: ["Расскажите о себе", "Tell me about yourself", "Розкажіть про себе"], answer: "x"),
        BankCard(id: "b", questions: ["Как работает async/await в Swift?", "Як працює async/await у Swift?"], answer: "y"),
    ]

    @Test func picksLanguage() {
        #expect(RecognitionVocabulary.prompt(cards: cards, language: "ru") == "Расскажите о себе Как работает async/await в Swift?")
        #expect(RecognitionVocabulary.prompt(cards: cards, language: "uk") == "Розкажіть про себе Як працює async/await у Swift?")
        #expect(RecognitionVocabulary.prompt(cards: cards, language: "en") == "Tell me about yourself")
    }

    @Test func respectsLimit() {
        #expect(RecognitionVocabulary.prompt(cards: cards, language: "ru", limit: 20) == "Расскажите о себе")
    }
}
