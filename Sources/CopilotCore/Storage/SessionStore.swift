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
    /// Обмены интервью с ответами владельца (COPILOT-06; решение владельца — сохранять в историю, срок R-18).
    public var exchanges: [SessionExchange] = []
    /// Настройки сессии из мастера (COPILOT-09); у сессий до 09 — nil.
    public var config: SessionConfig?
    /// Ваши фразы с временем — расшифровка по говорящим (COPILOT-09 R-14); у сессий до 09 — пусто.
    public var ownerUtterances: [Utterance] = []
    /// Разбор после End (COPILOT-09 R-13).
    public var review: SessionReview?

    public init(id: String, startedAt: Date, source: String?) {
        self.id = id
        self.startedAt = startedAt
        self.source = source
    }

    enum CodingKeys: String, CodingKey { case id, startedAt, endedAt, source, utterances, turns, exchanges, config, ownerUtterances, review }

    // Старые файлы истории без новых полей читаются (COPILOT-06).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        utterances = try c.decodeIfPresent([Utterance].self, forKey: .utterances) ?? []
        turns = try c.decodeIfPresent([TurnRecord].self, forKey: .turns) ?? []
        exchanges = try c.decodeIfPresent([SessionExchange].self, forKey: .exchanges) ?? []
        config = try? c.decodeIfPresent(SessionConfig.self, forKey: .config)
        ownerUtterances = (try? c.decodeIfPresent([Utterance].self, forKey: .ownerUtterances)) ?? []
        // Поврежденный разбор не мешает открыть расшифровку (AC-07).
        review = try? c.decodeIfPresent(SessionReview.self, forKey: .review)
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
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let file = url(for: session.id)
            try Self.encoder.encode(session).write(to: file, options: [.atomic, .completeFileProtection])
            // Расшифровки и ответы — личные данные: файл только для владельца (как отпечаток голоса, COPILOT-07).
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    /// Файлы, сохранённые до COPILOT-07 с правами 644, — только для владельца.
    public func restrictPermissions() {
        lock.withLock {
            guard FileManager.default.fileExists(atPath: directory.path) else { return }
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for f in files where f.pathExtension == "json" {
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: f.path)
            }
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
