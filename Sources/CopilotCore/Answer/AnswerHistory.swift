import Foundation

/// Одна версия ответа на вопрос: исходная подсказка, ответ сильной модели, уточнение из чата (COPILOT-09 R-09, R-10).
public struct AnswerVersion: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable {
        case hint, bank, strong, screenshot, refine
    }

    public enum Status: Equatable, Sendable {
        /// Запрос отправлен, текста ещё нет.
        case waiting
        case streaming
        case complete
        /// Ответа не будет: причина (модели недоступны, ошибка) — с «Повторить».
        case failed(String)
        /// Прервано новым вопросом; уже пришедший текст остаётся помеченным как неполный.
        case cancelled
        /// «Нет в базе» (режим «только база»): ближайшие карточки.
        case noMatch([String])
    }

    public var id: Int
    public var kind: Kind
    public var text = ""
    /// «Groq · 1,1 с», «Bank · about-me · 91%».
    public var source = ""
    public var latency: Double?
    public var tags: [String] = []
    public var status: Status = .waiting
    /// Уточнение из чата («короче», «без Kafka»).
    public var instruction: String?

    public init(id: Int, kind: Kind, instruction: String? = nil) {
        self.id = id
        self.kind = kind
        self.instruction = instruction
    }

    public var isFinished: Bool {
        switch status {
        case .waiting, .streaming: false
        default: true
        }
    }
}

/// Вопрос и его ответы.
public struct AnswerEntry: Equatable, Sendable, Identifiable {
    public var id: Int
    public var turnID: Int?
    public var question: String
    public var title: String
    public var versions: [AnswerVersion] = []
    public var selectedVersion = 0
    public var createdAt: Date

    public var current: AnswerVersion? { versions.indices.contains(selectedVersion) ? versions[selectedVersion] : versions.last }
}

/// История ответов сессии — COPILOT-09 R-08, R-09. Каждый запрос пишет только в свою версию (по id): поздние токены
/// отменённого или чужого запроса не попадают в видимый ответ (исследование ParakeetAI 4.3, 16.4).
public struct AnswerHistory: Equatable, Sendable {
    public private(set) var entries: [AnswerEntry] = []
    /// Показанный вопрос (индекс); nil — истории нет.
    public private(set) var selected: Int?
    /// Пользователь листает старые ответы — новый не перебивает просмотр, а появляется значок «новый ответ».
    public private(set) var hasUnseenNew = false
    public static let limit = 50
    private var nextID = 1

    public init() {}

    public var current: AnswerEntry? { selected.flatMap { entries.indices.contains($0) ? entries[$0] : nil } }
    public var isViewingLatest: Bool { selected == nil || selected == entries.count - 1 }
    /// «3 / 7».
    public var position: String? { selected.map { "\($0 + 1) / \(entries.count)" } }
    /// Предыдущий вопрос перед текущим — показывается приглушённым, пока новый ответ ещё готовится (R-08).
    public var previous: AnswerEntry? {
        guard let s = selected, s > 0 else { return nil }
        return entries[s - 1]
    }

    /// Новый вопрос; возвращает (вопрос, версия). Если смотрели последний — переходим к новому, иначе — значок.
    @discardableResult
    public mutating func begin(question: String, turnID: Int?, kind: AnswerVersion.Kind, at date: Date = Date()) -> (entry: Int, version: Int) {
        let following = isViewingLatest
        let entryID = takeID(), versionID = takeID()
        var entry = AnswerEntry(id: entryID, turnID: turnID, question: question, title: Self.title(for: question), createdAt: date)
        entry.versions = [AnswerVersion(id: versionID, kind: kind)]
        entries.append(entry)
        if entries.count > Self.limit {
            entries.removeFirst(entries.count - Self.limit)
            if let s = selected { selected = max(0, s - 1) }
        }
        if following { selected = entries.count - 1; hasUnseenNew = false } else { hasUnseenNew = true }
        return (entryID, versionID)
    }

    /// Новая версия того же вопроса (уточнение, сильная модель); показывается сразу.
    @discardableResult
    public mutating func beginVersion(of entryID: Int, kind: AnswerVersion.Kind, instruction: String? = nil) -> Int? {
        guard let i = index(of: entryID) else { return nil }
        let id = takeID()
        entries[i].versions.append(AnswerVersion(id: id, kind: kind, instruction: instruction))
        entries[i].selectedVersion = entries[i].versions.count - 1
        return id
    }

    /// Изменить версию по id — только её; несуществующая (вытесненная) — ничего не меняется.
    public mutating func update(entry entryID: Int, version versionID: Int, _ change: (inout AnswerVersion) -> Void) {
        guard let i = index(of: entryID), let j = entries[i].versions.firstIndex(where: { $0.id == versionID }) else { return }
        change(&entries[i].versions[j])
    }

    /// Не вопрос («—»): вопрос убирается, просмотр возвращается к предыдущему.
    public mutating func remove(entry entryID: Int) {
        guard let i = index(of: entryID) else { return }
        entries.remove(at: i)
        if entries.isEmpty {
            selected = nil
        } else if let s = selected, s >= i {
            // Удалён показанный или более ранний — показываем предыдущий (или первый).
            selected = max(0, s - 1)
        }
        if isViewingLatest { hasUnseenNew = false }
    }

    /// Незаконченные версии, кроме `except`, — прерваны (новый вопрос).
    public mutating func cancelUnfinished(except versionID: Int? = nil) {
        for i in entries.indices {
            for j in entries[i].versions.indices where !entries[i].versions[j].isFinished && entries[i].versions[j].id != versionID {
                entries[i].versions[j].status = .cancelled
            }
        }
    }

    public mutating func selectPrevious() { if let s = selected, s > 0 { selected = s - 1 } }
    public mutating func selectNext() {
        if let s = selected, s < entries.count - 1 { selected = s + 1 }
        if isViewingLatest { hasUnseenNew = false }
    }
    public mutating func selectLatest() {
        selected = entries.isEmpty ? nil : entries.count - 1
        hasUnseenNew = false
    }
    public mutating func selectVersion(_ index: Int) {
        guard let s = selected, entries[s].versions.indices.contains(index) else { return }
        entries[s].selectedVersion = index
    }

    public mutating func clear() {
        entries = []
        selected = nil
        hasUnseenNew = false
    }

    public func entry(_ id: Int) -> AnswerEntry? { index(of: id).map { entries[$0] } }

    private func index(of id: Int) -> Int? { entries.firstIndex { $0.id == id } }
    private mutating func takeID() -> Int { defer { nextID += 1 }; return nextID }

    /// Заголовок «Вопрос: …»: первое предложение-вопрос, без вводных слов, не длиннее 80 символов.
    public static func title(for question: String) -> String {
        var t = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if let q = t.firstIndex(of: "?") { t = String(t[...q]) }
        for lead in ["Uh ", "Эээ, ", "Ээ, ", "Ну ", "А ", "И ", "Так, ", "Okay, ", "So, "] where t.hasPrefix(lead) {
            t = String(t.dropFirst(lead.count))
        }
        if let first = t.first { t = first.uppercased() + t.dropFirst() }
        return t.count > 80 ? String(t.prefix(79)) + "…" : t
    }
}
