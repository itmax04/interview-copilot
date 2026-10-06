import Foundation

/// Сессия — R-19: реплики, ходы, ответ, источник, модель, задержки, токены. Аудио не сохраняется (R-04).
public struct SessionRecord: Codable, Equatable, Sendable, Identifiable {
    public struct Utterance: Codable, Equatable, Sendable {
        public var id: Int
        public var text: String
        public var language: String
        public var at: Date

        public init(id: Int, text: String, language: String, at: Date) {
            self.id = id
            self.text = text
            self.language = language
            self.at = at
        }
    }

    public struct TurnRecord: Codable, Equatable, Sendable {
        public var id: Int
        public var question: String
        public var answer: String
        /// "bank" или провайдер (gemini / deepseek / anthropic).
        public var source: String
        public var model: String?
        public var cardID: String?
        public var forced: Bool
        public var cardShownMs: Double?
        public var firstTokenMs: Double?
        public var inputTokens: Int?
        public var outputTokens: Int?
        public var at: Date

        public init(id: Int, question: String, answer: String, source: String, model: String?, cardID: String?, forced: Bool,
                    cardShownMs: Double?, firstTokenMs: Double?, inputTokens: Int?, outputTokens: Int?, at: Date) {
            self.id = id; self.question = question; self.answer = answer; self.source = source; self.model = model
            self.cardID = cardID; self.forced = forced; self.cardShownMs = cardShownMs; self.firstTokenMs = firstTokenMs
            self.inputTokens = inputTokens; self.outputTokens = outputTokens; self.at = at
        }
    }

    public var id: String
    public var startedAt: Date
    public var endedAt: Date?
    public var source: String?
    public var utterances: [Utterance] = []
    public var turns: [TurnRecord] = []

    public init(id: String, startedAt: Date, source: String?) {
        self.id = id
        self.startedAt = startedAt
        self.source = source
    }
}

/// Хранилище истории: `…/sessions/<дата-время>.json`, удаление одной/всех, автоудаление старше срока (R-19, AC-12).
public final class SessionStore: @unchecked Sendable {
    public let directory: URL
    private let lock = NSLock()

    public init(directory: URL) {
        self.directory = directory
    }

    static let fileFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return f
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public func newSession(source: String?, at date: Date = Date()) -> SessionRecord {
        var id = Self.fileFormatter.string(from: date)
        var n = 2
        while FileManager.default.fileExists(atPath: url(for: id).path) {
            id = Self.fileFormatter.string(from: date) + "-\(n)"
            n += 1
        }
        return SessionRecord(id: id, startedAt: date, source: source)
    }

    func url(for id: String) -> URL { directory.appendingPathComponent("\(id).json") }

    public func save(_ session: SessionRecord) throws {
        try lock.withLock {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.encoder.encode(session).write(to: url(for: session.id), options: [.atomic, .completeFileProtection])
        }
    }

    /// Список сессий, новые сверху.
    public func list() -> [SessionRecord] {
        lock.withLock {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            return files.filter { $0.pathExtension == "json" }
                .compactMap { try? Self.decoder.decode(SessionRecord.self, from: Data(contentsOf: $0)) }
                .sorted { $0.startedAt > $1.startedAt }
        }
    }

    public func load(_ id: String) -> SessionRecord? {
        lock.withLock { try? Self.decoder.decode(SessionRecord.self, from: Data(contentsOf: url(for: id))) }
    }

    public func delete(_ id: String) throws {
        try lock.withLock {
            let u = url(for: id)
            if FileManager.default.fileExists(atPath: u.path) { try FileManager.default.removeItem(at: u) }
        }
    }

    public func deleteAll() throws {
        for s in list() { try delete(s.id) }
    }

    /// Удалить сессии старше `days` дней. Возвращает число удалённых.
    @discardableResult
    public func purge(olderThan days: Int, now: Date = Date()) -> Int {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        var removed = 0
        for s in list() where (s.endedAt ?? s.startedAt) < cutoff {
            if (try? delete(s.id)) != nil { removed += 1 }
        }
        return removed
    }
}
