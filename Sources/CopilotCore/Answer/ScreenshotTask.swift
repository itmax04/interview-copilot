import Foundation

/// Задача со скриншота — COPILOT-09 R-15: снимки в течение 30 с — к той же задаче (до 3), позже — новая.
/// Пока задача активна, она идет в запрос блоком `<active_task>`: голосовые уточнения «а сложность?», «а если…»
/// относятся к ней.
public struct ScreenshotTask: Equatable, Sendable, Identifiable {
    public var id: Int
    /// JPEG снимков по порядку.
    public var images: [Data]
    public var startedAt: Date
    public var lastShotAt: Date
    /// Решение модели целиком (Markdown: Task, Approach, Code, Complexity, Checks).
    public var solution = ""
    /// История ответов: вопрос, к которому пишутся версии решения.
    public var entryID: Int?

    public init(id: Int, image: Data, at date: Date) {
        self.id = id
        self.images = [image]
        self.startedAt = date
        self.lastShotAt = date
    }

    /// Условие из раздела «Task» решения — заголовок вопроса и строка в `<active_task>`.
    public var statement: String? { Self.section("Task", in: solution).map(Self.firstSentences) }

    /// Блок для промпта: условие, подход, сложность и код — коротко, код усечен.
    public var promptSummary: String? {
        guard !solution.isEmpty else { return nil }
        var parts: [String] = []
        if let s = Self.section("Task", in: solution) { parts.append("Task: \(s)") }
        if let s = Self.section("Approach", in: solution) { parts.append("Approach:\n\(s)") }
        if let s = Self.section("Complexity", in: solution) { parts.append("Complexity: \(s)") }
        if let code = Self.codeBlock(in: solution) {
            parts.append("Code:\n```\n\(code.count > 1_800 ? String(code.prefix(1_800)) + "\n…" : code)\n```")
        }
        // Модель ответила не по разделам — решение как есть, усеченное.
        if parts.isEmpty { parts.append(String(solution.prefix(2_000))) }
        return parts.joined(separator: "\n")
    }

    /// Текст раздела «**Name** — …» до следующего пронумерованного раздела.
    static func section(_ name: String, in text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.range(of: "**\(name)**", options: .caseInsensitive) != nil || t.range(of: "### \(name)", options: .caseInsensitive) != nil
        }) else { return nil }
        var out: [String] = []
        let head = lines[start].components(separatedBy: "**").last ?? ""
        let rest = head.trimmingCharacters(in: CharacterSet(charactersIn: " —–-:").union(.whitespaces))
        if !rest.isEmpty { out.append(rest) }
        for line in lines[(start + 1)...] {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") { break }
            if let first = t.first, first.isNumber, t.contains("**") { break }
            if t.hasPrefix("**") || t.hasPrefix("#") { break }
            if !t.isEmpty { out.append(t) }
        }
        let s = out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    static func codeBlock(in text: String) -> String? {
        guard let open = text.range(of: "```") else { return nil }
        let afterOpen = text[open.upperBound...]
        guard let newline = afterOpen.firstIndex(of: "\n"), let close = afterOpen[newline...].range(of: "```") else { return nil }
        let code = afterOpen[afterOpen.index(after: newline)..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return code.isEmpty ? nil : code
    }

    /// Первые 1–2 предложения, не длиннее 160 символов, без разметки.
    static func firstSentences(_ s: String) -> String {
        let plain = s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        let capitalized = plain.prefix(1).uppercased() + plain.dropFirst()
        return capitalized.count > 160 ? String(capitalized.prefix(159)) + "…" : capitalized
    }
}

/// Какая задача активна и куда идет новый снимок.
public struct ScreenshotTaskTracker: Sendable {
    /// Снимок в течение этого времени после предыдущего — та же задача.
    public static let sameTaskWindow: TimeInterval = 30
    public static let maxImages = 3
    /// Задача перестает быть активной через столько после последнего снимка или ответа о ней.
    public static let activeFor: TimeInterval = 15 * 60

    public private(set) var task: ScreenshotTask?
    private var nextID = 1
    private var lastUsedAt: Date?

    public init() {}

    /// Добавить снимок; `true` — новая задача.
    @discardableResult
    public mutating func add(_ image: Data, at date: Date = Date()) -> Bool {
        if var t = task, date.timeIntervalSince(t.lastShotAt) <= Self.sameTaskWindow, t.images.count < Self.maxImages {
            t.images.append(image)
            t.lastShotAt = date
            task = t
            lastUsedAt = date
            return false
        }
        task = ScreenshotTask(id: nextID, image: image, at: date)
        nextID += 1
        lastUsedAt = date
        return true
    }

    public mutating func setSolution(_ text: String, taskID: Int) {
        guard task?.id == taskID else { return }
        task?.solution = text
    }

    public mutating func setEntry(_ entryID: Int, taskID: Int) {
        guard task?.id == taskID else { return }
        task?.entryID = entryID
    }

    /// Вопрос о задаче — продлевает ее активность.
    public mutating func touch(at date: Date = Date()) { if task != nil { lastUsedAt = date } }

    /// Задача, которая идет в промпт: есть решение и прошло меньше 15 минут с последнего снимка или вопроса о ней.
    public func active(at date: Date = Date()) -> ScreenshotTask? {
        guard let task, !task.solution.isEmpty, let used = lastUsedAt, date.timeIntervalSince(used) <= Self.activeFor else { return nil }
        return task
    }

    /// Clear и конец сессии.
    public mutating func clear() {
        task = nil
        lastUsedAt = nil
    }
}

/// Короткий уточняющий вопрос без явного предмета («почему так?», «а сложность?», «а если массив большой?») —
/// COPILOT-09 R-16: относится к последнему ответу или активной задаче.
public enum FollowUpDetector {
    static let starts = [
        // ru
        "почему", "а почему", "а если", "что если", "а что если", "а как", "а сложность", "сложность", "а память", "а по памяти",
        "а можно", "можно быстрее", "можно ли быстрее", "а быстрее", "а зачем", "зачем так", "а другой", "а еще", "а ещё",
        "а в худшем", "а для", "а при", "объясните", "поясните", "а пример",
        // uk
        "чому", "а чому", "а якщо", "що якщо", "а що якщо", "а як", "а складність", "складність", "а пам'ять", "а пам’ять",
        "а можна", "можна швидше", "а навіщо", "навіщо так", "а інший", "а ще", "поясніть", "а приклад",
        // en
        "why", "what if", "and if", "how about", "what about", "complexity", "time complexity", "and the complexity",
        "can you do better", "can it be faster", "could you optimize", "any other way", "explain", "and memory",
    ]

    /// Явный новый предмет — не уточнение, даже если начинается похоже («а как вы работаете в команде?»).
    static let newTopicMarkers = ["вы ", "ви ", "you ", "ваш", "your", "расскажите", "розкажіть", "tell me"]

    public static func isFollowUp(_ question: String) -> Bool {
        let t = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let words = t.split(whereSeparator: { $0.isWhitespace }).count
        guard words > 0, words <= 9 else { return false }
        // Самое длинное подходящее начало; новый предмет ищется только после него («can you do better» — уточнение).
        guard let start = starts.filter({ t == $0 || t.hasPrefix($0 + " ") || t.hasPrefix($0 + ",") }).max(by: { $0.count < $1.count })
        else { return false }
        let rest = " " + t.dropFirst(start.count) + " "
        return !newTopicMarkers.contains { rest.contains(" " + $0) }
    }
}
