import Foundation

/// Активная тема / основной вопрос (билет) текущего диалога — E-02.
/// Сохраняется через всю цепочку уточняющих вопросов («А статья?» → «А винятки?» → «А строки?»),
/// чтобы контекстный поиск по материалам и LLM не теряли предмет разговора при перебиваниях.
public struct ActiveTopic: Equatable, Sendable {
    /// ID корневого обмена в `InterviewMemory`.
    public var rootExchangeID: Int?
    /// ID корневой карточки в `AnswerHistory` (для быстрого возврата «← К билету» на оверлее).
    public var rootEntryID: Int?
    /// Исходный (корневой) вопрос или билет.
    public var rootQuestion: String
    /// Короткий заголовок корневого вопроса для UI-бейджей.
    public var rootTitle: String
    /// Последние фразы владельца по этой теме (включая прерванный ответ).
    public var ownerLastSpoken: String
    /// Краткое содержание последней показанной подсказки по теме.
    public var lastShownHint: String
    /// Лучшие отрывки материалов, найденные для корневого вопроса (опорный контекст для доп. вопросов).
    public var rootMaterials: [MaterialHit]
    /// Количество подряд идущих доп. вопросов в этой цепочке.
    public var followUpDepth: Int
    /// Текст корня уже уточнён Whisper (COPILOT-17 R-05): второй раз не обновляется.
    public var rootRefined = false

    public init(rootExchangeID: Int? = nil, rootEntryID: Int? = nil, rootQuestion: String,
                rootTitle: String? = nil, ownerLastSpoken: String = "", lastShownHint: String = "",
                rootMaterials: [MaterialHit] = [], followUpDepth: Int = 0) {
        self.rootExchangeID = rootExchangeID
        self.rootEntryID = rootEntryID
        self.rootQuestion = rootQuestion
        self.rootTitle = rootTitle ?? AnswerHistory.title(for: rootQuestion)
        self.ownerLastSpoken = ownerLastSpoken
        self.lastShownHint = lastShownHint
        self.rootMaterials = rootMaterials
        self.followUpDepth = followUpDepth
    }

    /// Составной поисковый запрос для RAG при доп. вопросе: связывает корневую тему,
    /// прерванный хвост речи владельца (если есть) и текст самого уточнения.
    public func contextualSearchQuery(for followUpQuestion: String) -> String {
        var parts = [rootQuestion.trimmingCharacters(in: .whitespacesAndNewlines)]
        let spoken = ownerLastSpoken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !spoken.isEmpty {
            parts.append(String(spoken.suffix(220)))
        }
        parts.append(followUpQuestion.trimmingCharacters(in: .whitespacesAndNewlines))
        return parts.filter { !$0.isEmpty }.joined(separator: " — ")
    }

    /// Объединяет материалы, найденные по контекстному запросу, с опорными материалами корневого вопроса:
    /// приоритет отдаётся совпадениям из тех же документов, что уже использовались для билета,
    /// а случайные слабые фрагменты из чужих разделов отсекаются.
    public func mergeMaterials(followUpHits: [MaterialHit], maxCount: Int = 4, minOffTopicScore: Double = 0.52) -> [MaterialHit] {
        let rootSources = Set(rootMaterials.map(\.source))
        var combined: [MaterialHit] = []
        var seen = Set<String>()

        func appendIfNew(_ hit: MaterialHit) {
            let key = "\(hit.source)|\(hit.text.prefix(80))"
            guard seen.insert(key).inserted else { return }
            combined.append(hit)
        }

        // 1. Сначала свежие попадания из тех же документов, что и корневой билет.
        for hit in followUpHits where rootSources.contains(hit.source) {
            appendIfNew(hit)
        }
        // 2. Затем сильные попадания из других документов (только выше повышенного порога).
        for hit in followUpHits where !rootSources.contains(hit.source) && hit.score >= minOffTopicScore {
            appendIfNew(hit)
        }
        // 3. Опорные отрывки корневого билета (до 2), чтобы модель не потеряла исходные нормы/факты.
        for hit in rootMaterials.prefix(2) {
            appendIfNew(hit)
        }
        return Array(combined.prefix(maxCount))
    }

    /// Форматированный блок `<active_topic>` для промпта.
    public func promptBlock(redact: (String) -> String) -> String {
        var lines = ["Root question/topic: \(redact(rootQuestion))"]
        let spoken = ownerLastSpoken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !spoken.isEmpty {
            lines.append("Candidate's recent/interrupted speech on this topic: \(redact(String(spoken.suffix(1000))))")
        }
        let hint = lastShownHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !hint.isEmpty {
            lines.append("Last shown hint on this topic (may not have been said): \(redact(String(hint.prefix(600))))")
        }
        return "<active_topic>\n" + lines.joined(separator: "\n") + "\n</active_topic>"
    }
}

/// Whisper по звуку вопроса уточняет корень активного билета (COPILOT-17 R-05). Чистая логика: подсказка не
/// пересоздаётся, ничего не ожидается; только заголовки и корневой вопрос.
public enum TicketRootUpdate {
    public struct Outcome: Equatable, Sendable {
        public var charsOld: Int
        public var charsNew: Int
    }

    /// `nil` — без изменений. Охранные условия: ход — корень текущего билета (id обмена не проверяется: билет
    /// определяется карточкой), корень не менялся и ещё не уточнялся, текст не пустой, не «выдумка», не тот же.
    @discardableResult
    public static func apply(turn: Int, oldText: String, newText: String, audioSeconds: Double,
                             topic: inout ActiveTopic?, history: inout AnswerHistory) -> Outcome? {
        let old = oldText.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let t = topic, !t.rootRefined, let rootID = t.rootEntryID,
              !new.isEmpty, new != old,
              !HallucinationFilter.isLikely(new, audioSeconds: audioSeconds),
              let entry = history.entry(rootID), entry.turnID == turn,
              t.rootQuestion.trimmingCharacters(in: .whitespacesAndNewlines) == old,
              entry.question.trimmingCharacters(in: .whitespacesAndNewlines) == old else { return nil }
        history.refineRoot(entry: rootID, question: new)
        topic?.rootQuestion = new
        topic?.rootTitle = AnswerHistory.title(for: new)
        topic?.rootRefined = true
        return Outcome(charsOld: old.count, charsNew: new.count)
    }
}
