import Foundation

/// Память одного интервью — COPILOT-06. Обмены «вопрос интервьюера → что ответил владелец → подсказка модели».
/// Короткая память — последние обмены целиком; долгая — поиск похожих старых обменов по эмбеддингам (bge-m3, локально).
/// В промпт идёт только реально сказанное (R-05): ничего не пересказывается моделью.
public struct SessionExchange: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var question: String
    /// Фразы владельца после вопроса, по порядку (с микрофона на созвоне, COPILOT-05 R-07).
    public var answer: [String]
    /// Подсказка, которую показала модель (для разбора после звонка; в промпт не идёт).
    public var hint: String?
    public var askedAt: Date
    /// Ход приложения, к которому относится обмен (COPILOT-07): подсказка находит свой обмен по нему, даже если
    /// текст вопроса уже заменён уточнённым (Whisper) или такой же вопрос задан дважды. В старых файлах истории — nil.
    public var turnID: Int?

    public init(id: Int, question: String, answer: [String] = [], hint: String? = nil, askedAt: Date, turnID: Int? = nil) {
        self.id = id
        self.question = question
        self.answer = answer
        self.hint = hint
        self.askedAt = askedAt
        self.turnID = turnID
    }

    public var answerText: String { answer.joined(separator: " ") }
}

/// Что из истории идёт в запрос к модели.
public struct MemoryContext: Sendable, Equatable {
    public struct Item: Sendable, Equatable {
        public var minutesAgo: Int
        public var question: String
        public var answer: String
        /// Ответ не записан — подсказка, которую видел владелец (может быть не сказана): факты держать согласованными.
        public var shownHint: String
        public init(minutesAgo: Int, question: String, answer: String, shownHint: String = "") {
            self.minutesAgo = minutesAgo
            self.question = question
            self.answer = answer
            self.shownHint = shownHint
        }
    }

    /// Последние обмены по порядку.
    public var recent: [Item] = []
    /// Старые обмены, найденные по смыслу вопроса.
    public var earlier: [Item] = []
    /// Интервьюер явно ссылается на сказанное раньше.
    public var backReference = false

    public init(recent: [Item] = [], earlier: [Item] = [], backReference: Bool = false) {
        self.recent = recent
        self.earlier = earlier
        self.backReference = backReference
    }

    public var isEmpty: Bool { recent.isEmpty && earlier.isEmpty }
    /// Есть ли в контексте хоть один записанный ответ кандидата (показанные подсказки не в счёт).
    public var hasRecordedAnswers: Bool { (recent + earlier).contains { !$0.answer.isEmpty } }
}

public final class InterviewMemory: @unchecked Sendable {
    /// Решение владельца «средне»: 4 последних обмена целиком + 3 найденных старых (~+1,5 тыс. токенов на запрос).
    public static let recentCount = 4
    public static let retrievedCount = 3
    /// Порог сходства bge-m3 для «та же тема»; при явной отсылке к прошлому — мягче (подбор — eval `memory`).
    public static let minScore: Float = 0.55
    public static let backReferenceMinScore: Float = 0.35
    /// Лимиты текста одного обмена в промпте.
    public static let maxQuestionChars = 300
    public static let maxAnswerChars = 500
    /// Показанная подсказка вместо незаписанного ответа — короче: только опорные факты.
    public static let maxHintChars = 300

    /// Подсказка без разметки, в одну строку.
    static func plainHint(_ hint: String?) -> String {
        guard let hint else { return "" }
        let flat = hint.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "•", with: ";")
            .split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(flat.prefix(maxHintChars))
    }

    private let lock = NSLock()
    private var exchanges: [SessionExchange] = []
    private var embeddings: [Int: [Float]] = [:]
    private var nextID = 1

    public private(set) var sessionID = UUID()

    public init() {}

    /// Новое интервью: память очищается (R-06 COPILOT-06 — сессии не смешиваются).
    public func reset() {
        lock.withLock {
            exchanges.removeAll()
            embeddings.removeAll()
            nextID = 1
            sessionID = UUID()
        }
    }

    public var all: [SessionExchange] { lock.withLock { exchanges } }

    @discardableResult
    public func addQuestion(_ text: String, turnID: Int? = nil, at date: Date = Date()) -> Int {
        lock.withLock {
            let e = SessionExchange(id: nextID, question: text, askedAt: date, turnID: turnID)
            nextID += 1
            exchanges.append(e)
            return e.id
        }
    }

    /// Фраза владельца относится к последнему вопросу. До первого вопроса — не сохраняется (нечему отвечать).
    public func addAnswer(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.withLock {
            guard !exchanges.isEmpty else { return }
            exchanges[exchanges.count - 1].answer.append(trimmed)
            embeddings[exchanges[exchanges.count - 1].id] = nil   // ответ изменился — эмбеддинг пересчитать
        }
    }

    /// Уточнённый текст реплики (Whisper, R-37) заменяет быстрый в вопросах и ответах последних обменов, где он встречается.
    public func reviseText(_ old: String, to new: String) {
        let old = old.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !old.isEmpty, !new.isEmpty, old != new else { return }
        lock.withLock {
            for i in exchanges.indices.reversed().prefix(3) {
                var changed = false
                if exchanges[i].question.contains(old) {
                    exchanges[i].question = exchanges[i].question.replacingOccurrences(of: old, with: new)
                    changed = true
                }
                // Ответ владельца в самопроверке (⌃⌥A) — тоже черновик Parakeet до уточнения (COPILOT-07).
                if let j = exchanges[i].answer.lastIndex(of: old) {
                    exchanges[i].answer[j] = new
                    changed = true
                }
                if changed { embeddings[exchanges[i].id] = nil }
            }
        }
    }

    /// Подсказка, показанная на ход. По номеру хода, а не по тексту: уточнение Whisper (~3 с) приходит раньше конца
    /// ответа медленного провайдера и меняет текст вопроса — поиск по тексту терял подсказку.
    public func setHint(_ text: String, forTurn turnID: Int) {
        lock.withLock {
            guard let i = exchanges.lastIndex(where: { $0.turnID == turnID }) else { return }
            exchanges[i].hint = text
        }
    }

    /// Модель решила, что это не вопрос («—»): обмен без ответа убирается, чтобы обрывки («Є таке питання.»)
    /// не занимали место последних обменов в промпте. Возвращает true, если обмен удалён.
    @discardableResult
    public func dropUnanswered(turnID: Int) -> Bool {
        lock.withLock {
            guard let i = exchanges.lastIndex(where: { $0.turnID == turnID }), exchanges[i].answer.isEmpty else { return false }
            embeddings[exchanges[i].id] = nil
            exchanges.remove(at: i)
            return true
        }
    }

    /// Контекст для вопроса. `embed` — эмбеддинг текста (bge-m3); без него — только последние обмены.
    /// Текущий вопрос в историю не входит, пока на него нет ответа: обмен хода `turnID`, а без номера — последний обмен
    /// с тем же текстом.
    public func context(for question: String, turnID: Int? = nil, now: Date = Date(),
                        embed: ((String) -> [Float]?)? = nil) -> MemoryContext {
        var history = all
        if let turnID {
            history.removeAll { $0.turnID == turnID && $0.answer.isEmpty }
        } else if let last = history.last, last.question == question, last.answer.isEmpty {
            history.removeLast()
        }
        let backReference = ReferenceDetector.isBackReference(question)
        func item(_ e: SessionExchange) -> MemoryContext.Item {
            .init(minutesAgo: max(0, Int(now.timeIntervalSince(e.askedAt) / 60)),
                  question: String(e.question.prefix(Self.maxQuestionChars)),
                  answer: String(e.answerText.prefix(Self.maxAnswerChars)),
                  shownHint: e.answer.isEmpty ? Self.plainHint(e.hint) : "")
        }
        let recent = Array(history.suffix(Self.recentCount))
        let older = Array(history.dropLast(Self.recentCount))
        var context = MemoryContext(recent: recent.map(item), backReference: backReference)
        guard !older.isEmpty, let embed, let query = embed(question) else { return context }
        let minScore = backReference ? Self.backReferenceMinScore : Self.minScore
        var scored: [(SessionExchange, Float)] = []
        for e in older {
            guard let v = embedding(for: e, embed: embed) else { continue }
            let score = zip(query, v).reduce(0) { $0 + $1.0 * $1.1 }
            if score >= minScore { scored.append((e, score)) }
        }
        let top = scored.sorted { $0.1 > $1.1 }.prefix(Self.retrievedCount).map(\.0).sorted { $0.id < $1.id }
        context.earlier = top.map(item)
        return context
    }

    private func embedding(for e: SessionExchange, embed: (String) -> [Float]?) -> [Float]? {
        if let cached = lock.withLock({ embeddings[e.id] }) { return cached }
        guard let v = embed("\(e.question) \(e.answerText)") else { return nil }
        lock.withLock { embeddings[e.id] = v }
        return v
    }
}

/// Отсылки к сказанному раньше (uk / ru / en) — COPILOT-06 R-03.
public enum ReferenceDetector {
    /// Основы слов, а не формы: «ви згадува» — и «згадували», и «згадувала»; «поверне/поверні» — «повернемо(ся)»,
    /// «повернімо(ся)» (живой тест COPILOT-06: «Повернемо себе до…» не распознавалось).
    static let markers: [String] = [
        // ru
        "вернёмся", "вернемся", "вернуться к", "вернусь к", "возвращаясь", "ранее", "раньше", "предыдущ", "в начале",
        "вы говорил", "вы сказал", "вы упоминал", "вы упомянул", "вы рассказывал", "как вы сказали", "уточните", "подробнее о",
        // uk
        "повернемо", "повернімо", "повернутися до", "повертаючись", "раніше", "попередн", "на початку",
        "ви казал", "ви сказал", "ви згадува", "ви згадал", "ви говорил", "ви розповідал", "як ви сказали",
        "уточніть", "детальніше про",
        // en
        "go back to", "back to", "earlier", "previous", "you mentioned", "you said", "you told", "you were saying",
        "you talked about", "at the beginning", "as you said", "elaborate on", "more about what you",
    ]

    public static func isBackReference(_ text: String) -> Bool {
        let lower = text.lowercased()
        return markers.contains { lower.contains($0) }
    }
}
