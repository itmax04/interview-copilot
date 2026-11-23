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

/// Короткий уточняющий вопрос без явного предмета («почему так?», «а сложность?», «а статья?», «а винятки?») —
/// COPILOT-09 R-16 + E-02 (экзамен и перебивания): относится к активной теме, последнему ответу или задаче.
public enum FollowUpDetector {
    static let starts = [
        // ru — общие и кодинг
        "почему", "а почему", "а если", "что если", "а что если", "а как", "а сложность", "сложность", "а память", "а по памяти",
        "а можно", "можно быстрее", "можно ли быстрее", "а быстрее", "а зачем", "зачем так", "а другой", "а еще", "а ещё",
        "а в худшем", "а для", "а при", "объясните", "поясните", "а пример",
        // ru — экзамен и перебивания (E-02)
        "статья", "какая статья", "а статья", "по какой статье", "исключения", "а исключения", "есть исключения", "какие исключения",
        "сроки", "срок", "какие сроки", "а сроки", "какой срок", "а срок", "последствия", "какие последствия", "а последствия",
        "основания", "какие основания", "а основания", "условия", "какие условия", "а условия", "признаки", "а признаки",
        "ответственность", "какая ответственность", "а ответственность", "порядок", "какой порядок", "субъекты",
        "структура", "какая структура", "а какая структура", "а структура", "методы", "какие методы", "а какие методы",
        "виды", "какие виды", "а какие виды", "полномочия", "какие полномочия", "а полномочия", "санкции", "какие санкции", "а какие санкции",
        "в зависимости от", "а в зависимости от", "в чем особенность", "в чём особенность", "особенность", "особенности",
        "классифицируйте их", "назовите их",
        "обоснуйте", "уточните", "конкретнее", "а конкретнее", "подробнее", "а подробнее", "пример", "приведите пример",
        "чем отличается", "в чем разница", "в чём разница", "а разница", "а в этом случае", "а в каком случае", "а если наоборот",
        "стоп", "подождите", "а на основании", "откуда это",
        // uk — общие и кодинг
        "чому", "а чому", "а якщо", "що якщо", "а що якщо", "а як", "а складність", "складність", "а пам'ять", "а пам’ять",
        "а можна", "можна швидше", "а навіщо", "навіщо так", "а інший", "а ще", "поясніть", "а приклад",
        // uk — экзамен и перебивания (E-02)
        "стаття", "яка стаття", "а стаття", "за якою статтею", "винятки", "а винятки", "які винятки", "є винятки",
        "строки", "строк", "які строки", "а строки", "який строк", "а строк", "термін", "терміни", "який термін", "які терміни",
        "наслідки", "які наслідки", "а наслідки", "підстави", "які підстави", "а підстави", "умови", "які умови", "а умови",
        "ознаки", "а ознаки", "відповідальність", "яка відповідальність", "а відповідальність", "суб'єкти", "суб’єкти",
        "структура", "яка структура", "а яка структура", "а структура", "методи", "які методи", "а які методи",
        "види", "які види", "а які види", "повноваження", "які повноваження", "а повноваження", "санкції", "які санкції", "а які санкції",
        "залежно від", "а залежно від", "у чому особливість", "в чому особливість", "особливість", "особливості",
        "класифікуйте їх", "назвіть їх",
        "обґрунтуйте", "уточніть", "конкретніше", "а конкретніше", "детальніше", "а детальніше", "приклад", "наведіть приклад",
        "чим відрізняється", "у чому різниця", "в чому різниця", "а різниця", "а у цьому випадку", "а в цьому випадку",
        "а в якому випадку", "а якщо навпаки", "почекайте", "зачекайте", "а на підставі", "звідки це",
        // en
        "why", "what if", "and if", "how about", "what about", "complexity", "time complexity", "and the complexity",
        "can you do better", "can it be faster", "could you optimize", "any other way", "explain", "and memory",
        "exceptions", "any exceptions", "what exceptions", "example", "give an example", "elaborate", "clarify",
    ]

    /// Явный новый предмет — не уточнение, даже если начинается похоже («а как вы работаете в команде?»).
    static let newTopicMarkers = ["вы ", "ви ", "you ", "ваш", "your", "расскажите", "розкажіть", "tell me"]

    /// Явный переход к новому вопросу/билету — всегда сбрасывает уточнение.
    static let topicShiftMarkers = [
        "следующий вопрос", "наступне питання", "другой вопрос", "інше питання",
        "перейдем к", "перейдём к", "перейдемо до", "новый билет", "новий білет", "теперь про", "тепер про",
    ]

    /// Короткие анафорические указатели на только что сказанное (для уточнений).
    static let anaphoricMarkers = [
        "это", "этом", "этого", "этой", "эта", "эту", "эти", "их", "тут", "здесь", "него", "нее", "неё", "них", "таком случае", "этом случае",
        "це", "цьому", "цього", "цієї", "ця", "цю", "ці", "їх", "тут", "нього", "неї", "них", "такому випадку", "цьому випадку",
        "this", "that", "here", "in that case", "them",
    ]

    /// Начало фразы-вопроса, открывающей новый билет («назвіть…», «що таке…», «what is…»; COPILOT-17 R-03).
    /// Только в начале фразы и только с предметом после него: «а що таке це в цьому випадку?» и «назвіть їх» остаются уточнениями.
    static let newTicketOpeners = [
        "назвіть", "перелічіть", "охарактеризуйте", "розкрийте", "що таке", "що називається", "дайте характеристику",
        "назовите", "перечислите", "раскройте", "что такое", "что называется",
        "what is", "what are", "name the", "define", "describe", "explain",
    ]

    /// Явный старт нового экзаменационного билета (не уточнение, даже если короткий).
    static let newTicketMarkers = [
        "сформулюйте поняття", "сформулируйте понятие", "дайте визначення", "дайте определение",
    ]

    public static func isFollowUp(_ question: String) -> Bool {
        let t = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let words = t.split(whereSeparator: { $0.isWhitespace }).count
        guard words > 0, words <= 12 else { return false }
        let padded = " " + t + " "
        if topicShiftMarkers.contains(where: { padded.contains(" " + $0) }) { return false }
        // Самое длинное подходящее начало; новый предмет ищется только после него («can you do better» — уточнение).
        if let start = starts.filter({ t == $0 || t.hasPrefix($0 + " ") || t.hasPrefix($0 + ",") }).max(by: { $0.count < $1.count }) {
            let rest = " " + t.dropFirst(start.count) + " "
            return !newTopicMarkers.contains { rest.contains(" " + $0) }
        }
        // Короткая реплика со ссылкой на текущую тему («а в этом случае?», «що про це каже закон?», «класифікуйте їх…»).
        if words <= 11, !newTopicMarkers.contains(where: { padded.contains(" " + $0) }) {
            if anaphoricMarkers.contains(where: { padded.contains(" " + $0 + " ") }) { return true }
        }
        return false
    }

    /// Уточняющий детектор для режима «Экзамен» (при наличии активного билета):
    /// любой короткий вопрос ≤ 8 слов без маркера смены билета считается уточнением к активной теме.
    public static func isExamFollowUp(_ question: String) -> Bool {
        let t = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let words = t.split(whereSeparator: { $0.isWhitespace }).count
        guard words > 0 else { return false }
        let padded = " " + t + " "
        if topicShiftMarkers.contains(where: { padded.contains(" " + $0) }) { return false }
        if newTicketMarkers.contains(where: { padded.contains(" " + $0) }) { return false }
        if startsNewTicket(t) { return false }
        if isFollowUp(question) { return true }
        return words <= 8 && !newTopicMarkers.contains(where: { padded.contains(" " + $0) })
    }

    /// COPILOT-17 R-03: фраза начинается с вопросного зачина и после него есть предмет (≥ 2 слов, без указательных слов).
    static func startsNewTicket(_ normalized: String) -> Bool {
        guard let opener = newTicketOpeners.first(where: { normalized.hasPrefix($0 + " ") }) else { return false }
        let rest = " " + normalized.dropFirst(opener.count) + " "
        guard rest.split(whereSeparator: { $0.isWhitespace }).count >= 2 else { return false }
        return !anaphoricMarkers.contains { rest.contains(" " + $0 + " ") }
    }
}
