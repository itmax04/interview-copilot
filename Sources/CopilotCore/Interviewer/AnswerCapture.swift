import Foundation

/// Ответ владельца в ИИ-собеседовании: все фрагменты речи с микрофона до конца ответа (COPILOT-03, R-32).
/// Время — секунды монотонных часов вызывающего кода.
public struct AnswerCapture: Sendable {
    public let startedAt: Double
    public private(set) var partial = ""
    private var finals: [Int: String] = [:]
    private var pending: Set<Int> = []
    private var revising: Set<Int> = []
    private var speaking = false
    private var lastActivity: Double
    private var firstSpeech: Double?
    private var lastSpeechEnd: Double?
    public private(set) var finishRequestedAt: Double?

    public init(startedAt: Double) {
        self.startedAt = startedAt
        lastActivity = startedAt
    }

    public var text: String { finals.keys.sorted().compactMap { finals[$0] }.joined(separator: " ") }
    public var hasSpeech: Bool { !finals.isEmpty || !pending.isEmpty }
    /// Длительность ответа: от начала первой речи до конца последней.
    public var speechSeconds: Double? {
        guard let firstSpeech, let lastSpeechEnd, lastSpeechEnd >= firstSpeech else { return nil }
        return lastSpeechEnd - firstSpeech
    }

    public mutating func handle(_ event: TranscriptEvent, at now: Double) {
        switch event {
        case .speechStarted(let u):
            pending.insert(u)
            speaking = true
            if firstSpeech == nil { firstSpeech = now }
            lastActivity = now
        case .speechEnded(let u, _):
            if pending.contains(u) {
                speaking = false
                lastSpeechEnd = now
                lastActivity = now
            }
        case .partial(let u, let value):
            if pending.contains(u) { partial = value }
        case .final(let u, let value, _, _, _):
            guard pending.contains(u) || finals[u] == nil else { return }
            if !revising.contains(u) { pending.remove(u) }
            finals[u] = value
            partial = ""
            lastActivity = now
        case .revising(let u):
            revising.insert(u)
            pending.insert(u)
        case .discarded(let u, _), .foreignVoice(let u, _, _, _):
            // Чужой голос в ответе владельца (COPILOT-05 R-01) — как шум.
            pending.remove(u)
            revising.remove(u)
        case .revised(let u, let value, _):
            guard revising.remove(u) != nil else { return }
            finals[u] = value
            pending.remove(u)
            lastActivity = now
        }
    }

    /// Автозавершение: владелец сказал хоть что-то, всё распознано и тишина не короче `silence` секунд.
    public func shouldAutoFinish(at now: Double, silence: Double) -> Bool {
        guard silence > 0, finishRequestedAt == nil, !finals.isEmpty, pending.isEmpty, !speaking else { return false }
        return now - lastActivity >= silence
    }

    public mutating func requestFinish(at now: Double) {
        if finishRequestedAt == nil { finishRequestedAt = now }
    }

    /// После «Я ответил» ждём распознавания начатых фраз, но не дольше `timeout`.
    public func isComplete(at now: Double, timeout: Double = 15) -> Bool {
        guard let finishRequestedAt else { return false }
        return pending.isEmpty || now - finishRequestedAt >= timeout
    }
}

/// Строка отчёта ИИ-собеседования: вопрос (эталон) против услышанного, ответ владельца и его правка.
public struct InterviewTurnRecord: Codable, Sendable, Equatable {
    public let id: String
    public let index: Int
    public let language: String
    public let question: String
    public var heard: String
    public var questionWords: Int
    public var questionErrors: Int
    public var questionWER: Double
    public var latencyMs: Double?
    public var problem: String?
    public var provider: String?
    public var answer: String
    public var answerSeconds: Double?
    /// Правка владельцем распознанного ответа — эталон для WER на живом голосе.
    public var corrected: String?
    public var answerWords: Int?
    public var answerErrors: Int?
    public var answerWER: Double?

    public init(id: String, index: Int, language: String, question: String, result: TestCallResult?, provider: String?) {
        self.id = id
        self.index = index
        self.language = language
        self.question = question
        heard = result?.recognized ?? ""
        questionWords = result?.words ?? TranscriptComparison.words(question).count
        questionErrors = result?.errors ?? questionWords
        questionWER = result?.wer ?? 100
        latencyMs = result?.latencyMs
        problem = result?.problem
        self.provider = provider
        answer = ""
    }

    public mutating func correct(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            corrected = nil; answerWords = nil; answerErrors = nil; answerWER = nil
            return
        }
        let score = TranscriptComparison(reference: t, recognized: answer)
        corrected = t
        answerWords = score.referenceWords
        answerErrors = score.errors
        answerWER = score.wordErrorRate * 100
    }
}
