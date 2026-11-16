import Foundation
import Testing
@testable import CopilotCore
import CopilotEmbeddings

@Suite("COPILOT-13 — questions.yaml переживает любой текст ответа")
struct QuestionBankWriterSanitizingTests {
    private func roundTrip(_ card: BankCard) throws -> BankCard {
        let cards = try QuestionBankParser.parse(QuestionBankWriter.yaml([card]))
        try #require(cards.count == 1)
        return cards[0]
    }

    @Test("Разрыв строки Unicode в ответе (вставка из Pages, Word) не ломает файл",
          arguments: ["\u{2028}", "\u{2029}", "\u{0085}", "\u{000B}", "\u{000C}", "\r\n", "\r"])
    func unicodeLineBreakInAnswer(_ separator: String) throws {
        let card = BankCard(id: "q-1", questions: ["Расскажите о себе"], answer: "Первая строка\(separator)Вторая строка")
        let read = try roundTrip(card)
        #expect(read.answer == "Первая строка\nВторая строка")
        #expect(read.questions == ["Расскажите о себе"])
    }

    @Test("Управляющие символы в ответе и вопросе убираются, файл читается")
    func controlCharactersAreDropped() throws {
        let card = BankCard(id: "q-1", questions: ["Что такое\u{0007} CI\u{007F}?", "Вопрос\u{2028}в две строки"],
                            answer: "Ответ\u{0000} с\u{0008} мусором\u{009F}\u{FFFE}.\n\tВторая строка с табуляцией")
        let read = try roundTrip(card)
        #expect(read.questions == ["Что такое CI?", "Вопрос в две строки"])
        #expect(read.answer == "Ответ с мусором.\n\tВторая строка с табуляцией")
    }

    @Test("Обычный текст записывается как раньше")
    func plainTextIsUnchanged() throws {
        let card = BankCard(id: "about-me", questions: ["Tell me about yourself", "Розкажіть про себе — коротко: «хто ви»?"],
                            answer: "Я разработчик.\n\n- Swift — 6 лет\n- 🚀 запуск за 2 недели\n  # не комментарий", tags: ["STAR"],
                            status: .approved, prepared: true)
        #expect(try roundTrip(card) == card)
    }
}

@Suite("COPILOT-13 — текст из документа")
struct DocumentTextLineBreakTests {
    @Test("Мягкие переносы и разрывы страниц Word становятся переводами строк")
    func softBreaksBecomeNewlines() {
        let raw = "Что такое CI?\u{2028}Непрерывная интеграция.\u{2029}Что такое CD?\u{000C}Непрерывная доставка.\u{000B}Конец"
        #expect(DocumentText.normalize(raw) == "Что такое CI?\nНепрерывная интеграция.\nЧто такое CD?\nНепрерывная доставка.\nКонец")
    }

    @Test("Вопросы из такого текста разбираются по строкам")
    func importSeesSeparateQuestions() {
        let raw = "1. Расскажите о себе\u{2028}Я разработчик.\u{2029}2. Почему уходите?\u{2028}Хочу роста."
        let found = QuestionImport.parseByRules(DocumentText.normalize(raw))
        #expect(found == [ImportedQuestion(question: "Расскажите о себе", answer: "Я разработчик."),
                          ImportedQuestion(question: "Почему уходите?", answer: "Хочу роста.")])
    }
}

@Suite("COPILOT-13 — части документа для разбора моделью")
struct QuestionImportChunkTests {
    @Test("Длинный текст без пустых строк делится на части целиком, ничего не теряется")
    func longParagraphIsNotTruncated() {
        let lines = (0..<400).map { "Строка \($0): расскажите про опыт с технологией номер \($0)" }
        let text = lines.joined(separator: "\n")
        let chunks = QuestionImport.chunks(text, maxCharacters: 2_000)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.count <= 2_000 })
        let restored = chunks.flatMap { $0.components(separatedBy: "\n") }.filter { !$0.isEmpty }
        #expect(restored == lines)
    }

    @Test("Строка длиннее лимита режется на куски, а не обрезается")
    func longLineIsSplit() {
        let text = String(repeating: "я", count: 5_500)
        let chunks = QuestionImport.chunks(text, maxCharacters: 2_000)
        #expect(chunks.map(\.count) == [2_000, 2_000, 1_500])
    }

    @Test("Обычные абзацы собираются в части как раньше")
    func paragraphsAreGroupedAsBefore() {
        let paragraphs = (0..<10).map { "Абзац \($0) " + String(repeating: "x", count: 500) }
        let chunks = QuestionImport.chunks(paragraphs.joined(separator: "\n\n"), maxCharacters: 2_000)
        #expect(chunks.count == 4)
        #expect(chunks.joined(separator: "\n\n") == paragraphs.joined(separator: "\n\n"))
    }
}

@Suite("COPILOT-13 — загрузка файла в раздел профиля")
struct ProfileImportSameFileTests {
    @Test("Повторная загрузка сохранённого исходника не удаляет его")
    func importingStoredSourceKeepsIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("copilot-import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = ProfileLibrary(root: root)
        let profile = try library.create(name: "Тест")
        let original = root.appendingPathComponent("resume.txt")
        try Data("Опыт: Swift, 6 лет".utf8).write(to: original)
        try library.importFile(original, as: .resume, into: profile.id)

        let stored = library.sourcesDirectory(profile.id).appendingPathComponent("resume.txt")
        #expect(FileManager.default.fileExists(atPath: stored.path))
        let text = try library.importFile(stored, as: .resume, into: profile.id)

        #expect(text == "Опыт: Swift, 6 лет")
        #expect(FileManager.default.fileExists(atPath: stored.path))
        #expect(library.read(.resume, of: profile.id) == "Опыт: Swift, 6 лет")
    }
}

private final class HitCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func hit() { lock.withLock { value += 1 } }
}

@Suite("COPILOT-13 — наблюдение за файлом, которого ещё нет")
struct FileWatcherAppearTests {
    @Test("Файл появился после начала наблюдения — onChange вызывается")
    func reportsFileThatAppearsLater() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("copilot-appear-\(UUID().uuidString).yaml")
        defer { try? FileManager.default.removeItem(at: url) }
        let counter = HitCounter()
        let watcher = FileWatcher(url: url) { counter.hit() }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(200))
        try Data("- id: a".utf8).write(to: url)
        let deadline = Date().addingTimeInterval(5)
        while counter.count == 0, Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(counter.count > 0)
    }
}

@Suite("COPILOT-13 — эмбеддинг текста длиннее окна модели")
struct LongTextEmbeddingTests {
    static let modelPath = AppPaths.model(AppSettings.defaultEmbeddingModel).path

    // Без модели тест пропускается (в отчёте «skipped», а не «passed»); тот же путь проверяет eval `materials`.
    @Test("Длинный текст обрезается до окна модели, а не даёт ошибку",
          .enabled(if: FileManager.default.fileExists(atPath: LongTextEmbeddingTests.modelPath)))
    func longTextIsTruncatedNotRejected() throws {
        let path = Self.modelPath
        let embedder = try LlamaEmbedder(modelPath: path, useGPU: false)
        let sentence = "Мы перевели сервис оплаты на очереди сообщений и сократили время ответа. "
        let long = String(repeating: sentence, count: 80)   // ~5 800 символов, заметно больше 512 токенов
        let vectors = try embedder.embed([sentence, long])
        #expect(vectors.count == 2)
        #expect(vectors[1].count == vectors[0].count)
        #expect(abs(vectors[1].dot(vectors[1]) - 1) < 0.01)
        // Начало длинного текста — то же предложение: ближе к нему, чем посторонний текст (порог не зависит от модели).
        let other = try embedder.embed(["Прогноз погоды на завтра: дождь и сильный ветер."])[0]
        #expect(vectors[0].dot(vectors[1]) > vectors[0].dot(other))
    }
}

@Suite("COPILOT-13 — запись пустых вопросов и разрез длинной строки")
struct ReviewFollowUpTests {
    @Test("Вопрос, пустой после очистки, не пишется, и файл остаётся читаемым")
    func emptyQuestionIsSkipped() throws {
        let cards = [
            BankCard(id: "a", questions: ["\u{2028}", "Расскажите о себе"], answer: "Ответ", tags: [], status: .own, prepared: false),
            BankCard(id: "b", questions: ["\u{000B}"], answer: "Ответ", tags: [], status: .own, prepared: false),
        ]
        let parsed = try QuestionBankParser.parse(QuestionBankWriter.yaml(cards))
        #expect(parsed.map(\.id) == ["a"])
        #expect(parsed[0].questions == ["Расскажите о себе"])
    }

    @Test("Строка длиннее части режется по пробелу, текст не теряется")
    func longLineSplitsAtSpace() {
        let text = Array(repeating: "слово", count: 40).joined(separator: " ")   // 239 символов, без переводов строки
        let parts = QuestionImport.chunks(text, maxCharacters: 50)
        #expect(parts.count > 1)
        #expect(parts.allSatisfy { $0.count <= 50 })
        #expect(parts.flatMap { $0.split(separator: " ") }.allSatisfy { $0 == "слово" })
        #expect(parts.flatMap { $0.split(separator: " ") }.count == 40)
    }
}
