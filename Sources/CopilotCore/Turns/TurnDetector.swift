import Foundation

/// Завершённый ход (R-05): вопрос собеседника, на который нужен ответ.
public struct Turn: Sendable, Equatable {
    public var id: Int
    public var text: String
    /// Конец речи собеседника (мс, монотонное время) — начало отсчёта метрик AC-02/AC-03 (`turn_end`).
    public var speechEndedAt: Double
    /// Когда ход признан завершённым (мс).
    public var firedAt: Double
    /// ⌃⌥↩ «Answer now» — ход по команде владельца.
    public var forced: Bool
}

/// Определение хода — R-05, S-07. Чистая логика со временем «снаружи» (мс), чтобы её можно было прогнать на eval `turn`.
///
/// Ход завершён, когда одновременно: собеседник молчит ≥ T мс, в накопленной реплике ≥ 3 слов, владелец не говорит.
/// Реплика — все итоговые фразы с момента прошлого хода (вопрос может состоять из нескольких фраз).
/// Если фраза оборвана на запятой или служебном слове («который», «що», «and»…), ждём дольше (T + `continuationExtraMs`):
/// собеседник, скорее всего, продолжит («Расскажите о проекте, который… сделали в прошлом году»).
public struct TurnDetector: Sendable {
    public struct Config: Sendable {
        public var thresholdMs: Double = 700
        public var minWords = 3
        public var continuationExtraMs: Double = 1300
        /// Без наушников микрофон слышит динамики: начало «речи владельца» во время речи собеседника и в течение
        /// этого времени после неё (рассинхрон захвата и микрофона) считается эхом и не учитывается
        /// (handoff, «Известная проблема» P-03). Эхо начинается вместе с речью собеседника, а не после неё.
        public var echoGraceMs: Double = 150

        public init(thresholdMs: Double = 700) {
            self.thresholdMs = thresholdMs
        }
    }

    public var config: Config
    private var pending: [String] = []
    private var lastSpeechEnd: Double?
    private var interviewerSpeaking = false
    private var interviewerStoppedAt: Double?
    private var ownerSpeaking = false
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
        suppressed = false
    }

    /// Собеседник замолчал (конец фразы по VAD). Итоговый текст придёт позже — `phraseFinal`.
    public mutating func interviewerStoppedSpeaking(at t: Double) {
        interviewerSpeaking = false
        interviewerStoppedAt = t
    }

    /// Итоговый текст фразы. `speechEnd` — момент конца речи.
    public mutating func phraseFinal(_ text: String, speechEnd: Double) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        interviewerSpeaking = false
        interviewerStoppedAt = max(interviewerStoppedAt ?? speechEnd, speechEnd)
        guard !trimmed.isEmpty else { return }
        pending.append(trimmed)
        lastFinalText = trimmed
        lastSpeechEnd = speechEnd
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
            if !pending.isEmpty { suppressed = true }
        } else {
            ownerSpeaking = false
        }
    }

    /// Проверка по времени. Возвращает ход, если условия R-05 выполнены.
    public mutating func tick(at t: Double) -> Turn? {
        guard !interviewerSpeaking, !suppressed, let end = lastSpeechEnd, !pending.isEmpty else { return nil }
        // Собеседник уже договорил новую фразу, но её текст ещё распознаётся — ждём, иначе вопрос будет обрезан.
        if let stopped = interviewerStoppedAt, stopped > end { return nil }
        if ownerSpeaking {
            suppressed = true
            return nil
        }
        let text = pendingText
        guard Self.wordCount(text) >= config.minWords else { return nil }
        let wait = config.thresholdMs + (Self.looksUnfinished(text) ? config.continuationExtraMs : 0)
        guard t - end >= wait else { return nil }
        return fire(text: text, speechEnd: end, at: t, forced: false)
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
        return fire(text: text, speechEnd: lastSpeechEnd ?? t, at: t, forced: true)
    }

    /// Сброс (пауза S-08).
    public mutating func reset() {
        forceRequested = false
        pending.removeAll()
        lastSpeechEnd = nil
        interviewerSpeaking = false
        suppressed = false
    }

    private mutating func fire(text: String, speechEnd: Double, at t: Double, forced: Bool) -> Turn {
        let turn = Turn(id: nextID, text: text, speechEndedAt: speechEnd, firedAt: t, forced: forced)
        nextID += 1
        lastTurnText = text
        pending.removeAll()
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
}
