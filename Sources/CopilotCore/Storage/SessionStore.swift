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
    /// Когда владелец выключал свой микрофон в Copilot (COPILOT-18 D7): только время; у прежних сессий — пусто.
    public var micMutedIntervals: [MicMutedInterval] = []
    /// Разбор после End (COPILOT-09 R-13).
    public var review: SessionReview?

    public init(id: String, startedAt: Date, source: String?) {
        self.id = id
        self.startedAt = startedAt
        self.source = source
    }

    enum CodingKeys: String, CodingKey { case id, startedAt, endedAt, source, utterances, turns, exchanges, config, ownerUtterances, micMutedIntervals, review }

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
        micMutedIntervals = (try? c.decodeIfPresent([MicMutedInterval].self, forKey: .micMutedIntervals)) ?? []
        // Поврежденный разбор не мешает открыть расшифровку (AC-07).
        review = try? c.decodeIfPresent(SessionReview.self, forKey: .review)
    }
}

/// Хранилище истории: `…/sessions/<дата-время>.json`, удаление одной/всех, автоудаление старше срока (R-19, AC-12).
public final class SessionStore: @unchecked Sendable {
    public let directory: URL
    private let lock = NSLock()
    private var nextSuffix: [String: Int] = [:]

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
        let base = Self.fileFormatter.string(from: date)
        return lock.withLock {
            // Keep issued IDs reserved while asynchronous reviews can still refer to them.
            var n = nextSuffix[base] ?? 1
            var id: String
            repeat {
                id = n == 1 ? base : base + "-" + String(n)
                n += 1
            } while FileManager.default.fileExists(atPath: url(for: id).path)
            nextSuffix[base] = n
            return SessionRecord(id: id, startedAt: date, source: source)
        }
    }

    private func validID(_ id: String) -> Bool {
        !id.isEmpty && !id.contains("/") && !id.utf8.contains(0)
    }

    func url(for id: String) -> URL { directory.appendingPathComponent("\(id).json") }

    public func save(_ session: SessionRecord) throws {
        guard validID(session.id) else { throw CocoaError(.fileWriteInvalidFileName) }
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
                .compactMap { file -> SessionRecord? in
                    guard let record = try? Self.decoder.decode(SessionRecord.self, from: Data(contentsOf: file)),
                          record.id == file.deletingPathExtension().lastPathComponent else { return nil }
                    return record
                }
                .sorted { $0.startedAt > $1.startedAt }
        }
    }

    public func load(_ id: String) -> SessionRecord? {
        guard validID(id) else { return nil }
        return lock.withLock {
            guard let record = try? Self.decoder.decode(SessionRecord.self, from: Data(contentsOf: url(for: id))),
                  record.id == id else { return nil }
            return record
        }
    }

    public func delete(_ id: String) throws {
        guard validID(id) else { throw CocoaError(.fileWriteInvalidFileName) }
        try lock.withLock {
            let u = url(for: id)
            if FileManager.default.fileExists(atPath: u.path) { try FileManager.default.removeItem(at: u) }
        }
    }

    /// Вся история: удаляются все файлы сессий, в том числе те, что не читаются (поврежденные или старого формата) —
    /// «Удалить всю историю» не должно оставлять расшифровки на диске (COPILOT-12).
    public func deleteAll() throws {
        try lock.withLock {
            let files: [URL]
            do { files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) }
            catch let error as CocoaError where error.code == .fileReadNoSuchFile { return }
            for f in files where f.pathExtension == "json" { try FileManager.default.removeItem(at: f) }
        }
    }

    /// Время начала сессии из имени файла (`yyyy-MM-dd'T'HH-mm-ss` с необязательным суффиксом); nil — имя другого вида.
    static func startDate(fromFileName name: String) -> Date? {
        fileFormatter.date(from: String(name.prefix(19)))
    }

    /// Запас на смену часового пояса и перевод часов: имя файла пишется по местному времени.
    static let nameDateMargin: TimeInterval = 26 * 3600

    /// Удалить сессии старше `days` дней. Возвращает число удалённых.
    ///
    /// Сессия, начатая (по имени файла) заведомо позже порога, не читается вовсе: раньше каждый старт сессии разбирал
    /// на главном потоке JSON всей истории. Файл, который не читается (повреждён, старый формат), удаляется по времени
    /// изменения: раньше он переживал срок хранения навсегда, а в нём расшифровка (R-19).
    @discardableResult
    public func purge(olderThan days: Int, now: Date = Date()) -> Int {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return lock.withLock {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                      includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            var removed = 0
            for file in files where file.pathExtension == "json" {
                let named = Self.startDate(fromFileName: file.deletingPathExtension().lastPathComponent)
                if let named, named >= cutoff.addingTimeInterval(Self.nameDateMargin) { continue }
                let last: Date
                if let session = try? Self.decoder.decode(SessionRecord.self, from: Data(contentsOf: file)) {
                    last = session.endedAt ?? session.startedAt
                } else {
                    let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    guard let latest = [named, modified].compactMap({ $0 }).max() else { continue }
                    last = latest
                }
                if last < cutoff, (try? FileManager.default.removeItem(at: file)) != nil { removed += 1 }
            }
            return removed
        }
    }
}
