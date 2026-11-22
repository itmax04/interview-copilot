import Foundation

/// Завершённый ход (R-05): вопрос собеседника, на который нужен ответ.
public struct Turn: Sendable, Equatable {
    public var id: Int
    public var text: String
    /// Конец речи собеседника (мс, монотонное время).
    public var speechEndedAt: Double
    /// Когда ход признан завершённым (мс) — `turn_end`, начало отсчёта метрик AC-02/AC-03 («после завершения хода»).
    public var firedAt: Double
    /// ⌃⌥↩ «Answer now» — ход по команде владельца.
    public var forced: Bool
    /// Номера фраз хода (`TranscriptEvent.utterance`): по ним строится звук для повторного распознавания (COPILOT-15).
    public var utterances: [Int]
    /// Склейка текстов фраз — предварительный текст (R-04): годится для эвристик конца хода и как запасной,
    /// если повторное распознавание не удалось. `text` после повторного распознавания — итоговый вопрос.
    public var provisionalText: String

    public init(id: Int, text: String, speechEndedAt: Double, firedAt: Double, forced: Bool,
                utterances: [Int] = [], provisionalText: String? = nil) {
        self.id = id
        self.text = text
        self.utterances = utterances
        self.provisionalText = provisionalText ?? text
        self.speechEndedAt = speechEndedAt
        self.firedAt = firedAt
        self.forced = forced
    }
}

/// Определение хода — R-05, S-07. Чистая логика со временем «снаружи» (мс), чтобы её можно было прогнать на eval `turn`.
///
/// Ход завершён, когда одновременно: собеседник молчит ≥ T мс, в накопленной реплике ≥ 3 слов, владелец не говорит.
/// Реплика — все итоговые фразы с момента прошлого хода (вопрос может состоять из нескольких фраз).
/// Если фраза оборвана на запятой или служебном слове («который», «що», «and»…), ждём дольше (T + `continuationExtraMs`):
/// собеседник, скорее всего, продолжит («Расскажите о проекте, который… сделали в прошлом году»).
public struct TurnDetector: Sendable {
    public struct Config: Sendable {
        public var thresholdMs: Double = 1000
        public var minWords = 3
        public var continuationExtraMs: Double = 1300
        /// Без наушников микрофон слышит динамики: начало «речи владельца» во время речи собеседника и в течение
        /// этого времени после неё (рассинхрон захвата и микрофона) считается эхом и не учитывается
        /// (handoff, «Известная проблема» P-03). Эхо начинается вместе с речью собеседника, а не после неё.
        public var echoGraceMs: Double = 150
        /// Захват системного звука запаздывает относительно микрофона: «речь владельца», начавшаяся не раньше этого
        /// до начала речи собеседника, тоже считается эхом.
        public var echoLeadMs: Double = 500
        /// Сколько ждать итог закончившейся фразы, прежде чем считать его потерянным (R-38).
        public var staleFinalMs: Double = 8000
        /// «Собеседник говорит» дольше этого — событие конца речи потерялось (R-38).
        public var staleSpeechMs: Double = 30000
        /// Явный вопрос (COPILOT-04 R-02): пауза короче T. Не больше T. COPILOT-15 R-09: 600 мс (было 350) — звук вопроса
        /// должен быть полным, прежде чем он уйдёт на повторное распознавание.
        public var questionThresholdMs: Double = 600
        /// Считать явным вопросом и фразу, начатую вопросительным словом («как», «почему», «how»…), а не только «?».
        /// Выключено: на eval `turn` выигрыша не дало (те же 596 мс), а риск хода на оборванной фразе выше (handoff COPILOT-04).
        public var questionStarters = false
        /// Разрешить короткие доп. вопросы (1–2 слова: «А статья?», «Почему?», «Исключения?»), когда уже есть активная тема,
        /// и отбрасывать пустой бэкченнел («ага», «хорошо», «дякую»), чтобы не копился в `pending`.
        public var allowShortFollowUps = false

        public init(thresholdMs: Double = 1000) {
            self.thresholdMs = thresholdMs
        }
    }

    public var config: Config
    private var pending: [String] = []
    private var pendingUtterances: [Int] = []
    private var lastUtterances: [Int] = []
    private var lastSpeechEnd: Double?
    private var interviewerSpeaking = false
    private var interviewerStartedAt: Double?
    private var interviewerStoppedAt: Double?
    private var ownerSpeaking = false
    private var ownerStartedAt: Double?
    /// Владелец заговорил во время ожидания — автоответ на эту реплику не запускается (S-07).
    private var suppressed = false
    private var lastTurnText: String?
    /// ⌃⌥↩ нажали, пока итоговый текст фразы ещё распознаётся: ход — как только он придёт.
    private var forceRequested = false
    private var lastFinalText: String?
    private var nextID = 1

    public init(config: Config = Config()) {
        self.config = config
    }

    public var pendingText: String { pending.joined(separator: " ") }

    /// Собеседник начал говорить: ожидание хода сбрасывается до конца новой фразы.
    public mutating func interviewerStartedSpeaking(at t: Double) {
        interviewerSpeaking = true
        interviewerStartedAt = t
        suppressed = false
        // Микрофон услышал динамики раньше, чем захват системного звука, — это тоже эхо.
        if ownerSpeaking, let started = ownerStartedAt, t - started < config.echoLeadMs {
            ownerSpeaking = false
        }
    }

    /// Собеседник замолчал (конец фразы по VAD). Итоговый текст придёт позже — `phraseFinal`.
    public mutating func interviewerStoppedSpeaking(at t: Double) {
        interviewerSpeaking = false
        interviewerStoppedAt = t
    }

    /// Итоговый текст фразы. `speechEnd` — момент конца речи.
    public mutating func phraseFinal(_ text: String, speechEnd: Double, utterance: Int? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        interviewerSpeaking = false
        interviewerStoppedAt = max(interviewerStoppedAt ?? speechEnd, speechEnd)
        guard !trimmed.isEmpty else { return }
        // В активном диалоге пустой бэкченнел («ага», «хорошо», «дякую») не копим в `pending`,
        // чтобы он не склеивался потом со следующим вопросом в обрывочную кашу.
        if config.allowShortFollowUps, pending.isEmpty, Self.isBackchannel(trimmed) {
            return
        }
        pending.append(trimmed)
        if let utterance { pendingUtterances.append(utterance) }
        lastFinalText = trimmed
        lastSpeechEnd = speechEnd
    }

    /// Реплика без текста (шум): если это была последняя закончившаяся фраза, её итога больше не ждём (R-38).
    public mutating func phraseDiscarded(speechEnd: Double) {
        if let stopped = interviewerStoppedAt, speechEnd >= stopped { interviewerStoppedAt = lastSpeechEnd }
    }

    /// Состояние для диагностики «итоги идут, а ходов нет» (R-38), без текста реплик.
    public func debugState(at t: Double) -> String {
        let awaiting = interviewerStoppedAt.map { $0 > (lastSpeechEnd ?? -1) } ?? false
        return "pending_words=\(Self.wordCount(pendingText)) speaking=\(interviewerSpeaking) awaiting_final=\(awaiting) "
            + "suppressed=\(suppressed) owner=\(ownerSpeaking) since_end_ms=\(lastSpeechEnd.map { Int(t - $0) } ?? -1)"
    }

    /// Ход по запросу ⌃⌥↩, ожидавший итогового текста. Вызывать после `phraseFinal`.
    public mutating func takeRequestedForce(at t: Double) -> Turn? {
        guard forceRequested, !pending.isEmpty else { return nil }
        forceRequested = false
        return fire(text: pendingText, speechEnd: lastSpeechEnd ?? t, at: t, forced: true)
    }

    public mutating func setOwnerSpeaking(_ speaking: Bool, at t: Double) {
        if speaking {
            let echo = interviewerSpeaking || (interviewerStoppedAt.map { t - $0 < config.echoGraceMs } ?? false)
            guard !echo else { return }
            ownerSpeaking = true
            ownerStartedAt = t
            if !pending.isEmpty { suppressed = true }
        } else {
            ownerSpeaking = false
        }
    }

    /// Проверка по времени. Возвращает ход, если условия R-05 выполнены.
    public mutating func tick(at t: Double) -> Turn? {
        // Страховка (R-38): VAD закрывает фразу не позже 25 с; если конца речи нет дольше — событие потерялось.
        if interviewerSpeaking, let started = interviewerStartedAt, t - started > config.staleSpeechMs { interviewerSpeaking = false }
        guard !interviewerSpeaking, !suppressed, let end = lastSpeechEnd, !pending.isEmpty else { return nil }
        // Собеседник уже договорил новую фразу, но её текст ещё распознаётся — ждём, иначе вопрос будет обрезан.
        // Итог, не пришедший за `staleFinalMs`, больше не ждём (R-38).
        if let stopped = interviewerStoppedAt, stopped > end {
            guard t - stopped > config.staleFinalMs else { return nil }
            interviewerStoppedAt = end
        }
        if ownerSpeaking {
            // Если владелец начал отвечать после вопроса — подавляем автоход (S-07).
            // При активной теме и коротком перебивании (владелец говорил ДО экзаменатора и замолкает в пределах 600 мс)
            // даём владельцу договорить хвост, не глуша вопрос экзаменатора навсегда.
            let isBriefBargeInYield = config.allowShortFollowUps
                && (ownerStartedAt ?? .infinity) < (interviewerStartedAt ?? 0)
                && (t - end) < 600
            if !isBriefBargeInYield { suppressed = true }
            return nil
        }
        let text = pendingText
        let words = Self.wordCount(text)
        if words >= config.minWords {
            guard t - end >= waitMs(for: text) else { return nil }
            return fire(text: text, speechEnd: end, at: t, forced: false)
        }
        // Короткий доп. вопрос (1–2 слова: «А статья?», «Почему?», «Исключения?») при активной теме — ждём полную паузу T.
        if config.allowShortFollowUps, words >= 1, Self.isShortFollowUp(text) {
            guard t - end >= config.thresholdMs else { return nil }
            return fire(text: text, speechEnd: end, at: t, forced: false)
        }
        return nil
    }

    /// Сколько ждать после конца речи: фраза оборвана — дольше T, явный вопрос — короче (R-05, COPILOT-04 R-02).
    func waitMs(for text: String) -> Double {
        if Self.looksUnfinished(text) { return config.thresholdMs + config.continuationExtraMs }
        if looksLikeQuestion(text) { return min(config.questionThresholdMs, config.thresholdMs) }
        return config.thresholdMs
    }

    /// Текст для опережающего запроса (COPILOT-04 R-01): реплика выглядит законченной и, скорее всего, станет ходом,
    /// но пауза T ещё не истекла. Модель начинает отвечать заранее; ход с тем же текстом забирает готовый ответ.
    /// nil — собеседник говорит, итог фразы ещё распознаётся, владелец говорит, мало слов или фраза оборвана.
    public func draft(at t: Double) -> String? {
        guard !interviewerSpeaking, !suppressed, !ownerSpeaking, let end = lastSpeechEnd, !pending.isEmpty else { return nil }
        if let stopped = interviewerStoppedAt, stopped > end { return nil }
        let text = pendingText
        guard Self.wordCount(text) >= config.minWords, !Self.looksUnfinished(text) else { return nil }
        return text
    }

    /// Черновик вместе с номерами фраз (COPILOT-15 R-08): по ним звук уходит на повторное распознавание.
    /// nil — как у `draft(at:)`, либо у накопленных фраз нет номеров (тогда звука для повторного распознавания нет).
    public func draftSnapshot(at t: Double) -> (text: String, utterances: [Int])? {
        guard let text = draft(at: t), !pendingUtterances.isEmpty else { return nil }
        return (text, pendingUtterances)
    }

    /// ⌃⌥↩: немедленный ход по последней реплике, даже если условия не выполнены (R-05).
    /// Если собеседник говорит или его фраза ещё распознаётся — ход будет сразу по приходе итогового текста.
    public mutating func force(at t: Double) -> Turn? {
        let awaitingFinal = interviewerSpeaking || (interviewerStoppedAt.map { $0 > (lastSpeechEnd ?? -1) } ?? false)
        if pending.isEmpty, awaitingFinal {
            forceRequested = true
            return nil
        }
        let text = pending.isEmpty ? (lastFinalText ?? lastTurnText ?? "") : pendingText
        guard !text.isEmpty else { return nil }
        return fire(text: text, speechEnd: lastSpeechEnd ?? t, at: t, forced: true,
                    utterances: pending.isEmpty ? lastUtterances : pendingUtterances)
    }

    /// Ход по тексту, который отбросил фильтр (COPILOT-05 S-08): владелец решил ответить на него сам.
    public mutating func forceText(_ text: String, at t: Double) -> Turn {
        fire(text: text, speechEnd: t, at: t, forced: true, utterances: [])
    }

    /// Сброс (пауза S-08).
    public mutating func reset() {
        forceRequested = false
        pending.removeAll()
        pendingUtterances.removeAll()
        lastSpeechEnd = nil
        interviewerSpeaking = false
        interviewerStoppedAt = nil
        ownerSpeaking = false
        ownerStartedAt = nil
        suppressed = false
    }

    private mutating func fire(text: String, speechEnd: Double, at t: Double, forced: Bool, utterances: [Int]? = nil) -> Turn {
        let used = utterances ?? pendingUtterances
        let turn = Turn(id: nextID, text: text, speechEndedAt: speechEnd, firedAt: t, forced: forced, utterances: used)
        nextID += 1
        lastTurnText = text
        if !used.isEmpty { lastUtterances = used }
        pending.removeAll()
        pendingUtterances.removeAll()
        suppressed = false
        return turn
    }

    static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace }.filter { $0.contains { $0.isLetter || $0.isNumber } }.count
    }

    /// Служебные слова, после которых фраза обычно продолжается (uk / ru / en).
    static let continuationWords: Set<String> = [
        // ru
        "и", "а", "но", "или", "что", "чтобы", "который", "которая", "которое", "которые", "когда", "если", "потому",
        "как", "где", "в", "на", "с", "со", "по", "о", "об", "про", "для", "к", "у", "из", "от", "это", "так",
        // uk
        "і", "й", "та", "але", "або", "що", "щоб", "який", "яка", "яке", "які", "коли", "якщо", "тому", "де", "до",
        "з", "зі", "із", "від", "для", "про", "це",
        // en
        "and", "or", "but", "so", "that", "which", "who", "when", "if", "because", "the", "a", "an", "to", "of",
        "in", "on", "at", "for", "with", "about", "your", "my", "is", "are", "was", "were", "how", "what",
    ]

    /// Вопросительные слова в начале фразы (uk / ru / en) — только при `questionStarters`.
    static let questionStarters: Set<String> = [
        "как", "почему", "зачем", "что", "какой", "какая", "какое", "какие", "когда", "где", "сколько", "кто", "чем",
        "як", "чому", "навіщо", "що", "який", "яка", "яке", "які", "коли", "де", "скільки", "хто", "чим", "чи",
        "how", "why", "what", "which", "when", "where", "who", "can", "could", "would", "do", "does", "did", "have", "is", "are",
    ]

    /// Явный вопрос: последняя фраза заканчивается «?» (Parakeet ставит его по интонации) или, при `questionStarters`,
    /// начинается вопросительным словом.
    func looksLikeQuestion(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("?") { return true }
        guard config.questionStarters, let last = pending.last else { return false }
        let first = last.split { $0.isWhitespace }.first.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) } ?? ""
        return Self.questionStarters.contains(first)
    }

    static func looksUnfinished(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return false }
        if "?!.…".contains(last) { return false }
        if ",;:-—".contains(last) { return true }
        let lastWord = trimmed.split { $0.isWhitespace }.last.map {
            $0.lowercased().trimmingCharacters(in: .punctuationCharacters)
        } ?? ""
        return continuationWords.contains(lastWord)
    }

    /// Пустые подтверждения/реакции собеседника (бэкченнел), не требующие ответа.
    private static let backchannels: Set<String> = [
        "ага", "угу", "да", "да да", "так", "так так", "добре", "хорошо", "понял", "поняла", "понятно",
        "зрозуміло", "ясно", "окей", "ок", "ok", "okay", "спасибо", "дякую", "thanks", "thank you",
        "продолжайте", "продовжуйте", "дальше", "далі", "слушаю", "слухаю", "мгм", "угум", "супер", "отлично", "чудово",
    ]

    /// Короткие ключевые слова уточнений (1–2 слова) на экзамене и интервью (RU / UK / EN).
    private static let shortFollowUpKeywords: Set<String> = [
        // ru
        "почему", "зачем", "откуда", "статья", "статью", "статьи", "исключения", "исключение", "сроки", "срок",
        "пример", "примеры", "подробнее", "конкретнее", "уточните", "обоснуйте", "последствия", "основания",
        "разница", "отличие", "условия", "признаки", "ответственность", "сложность", "память", "альтернативы",
        // uk
        "чому", "навіщо", "звідки", "стаття", "статтю", "статті", "винятки", "виняток", "строки", "строк",
        "термін", "терміни", "приклад", "приклади", "детальніше", "конкретніше", "уточніть", "обґрунтуйте",
        "наслідки", "підстави", "різниця", "відмінність", "умови", "ознаки", "відповідальність", "складність", "пам'ять",
        // en
        "why", "example", "examples", "exceptions", "complexity", "memory", "explain", "elaborate", "alternatives",
    ]

    static func normalizedShort(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public static func isBackchannel(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("?") { return false }
        let norm = normalizedShort(trimmed)
        return !norm.isEmpty && backchannels.contains(norm)
    }

    public static func isShortFollowUp(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let norm = normalizedShort(trimmed)
        guard !norm.isEmpty, !backchannels.contains(norm) else { return false }
        if trimmed.hasSuffix("?") { return true }
        let words = norm.split(separator: " ").map(String.init)
        return words.contains { shortFollowUpKeywords.contains($0) }
    }
}
