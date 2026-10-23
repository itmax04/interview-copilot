import Foundation

public struct TestCallClip: Codable, Sendable, Equatable {
    public let id: String
    public let language: String
    public let title: String
    public let text: String
    public let file: String

    public init(id: String, language: String, title: String, text: String, file: String) {
        self.id = id; self.language = language; self.title = title; self.text = text; self.file = file
    }
}

public struct TestCallResult: Codable, Sendable, Equatable {
    public let trialID: String
    public let clipID: String
    public let language: String
    public let reference: String
    public let recognized: String
    public let words: Int
    public let errors: Int
    public let wer: Double
    public let latencyMs: Double?
    public let problem: String?
}

/// Собирает все VAD-фрагменты одной воспроизводимой фразы, прежде чем выставлять оценку.
public struct TestCallTrial: Sendable {
    public let id: String
    public let clip: TestCallClip
    public private(set) var partial = ""
    public private(set) var result: TestCallResult?
    private var pending: Set<Int> = []
    private var revising: Set<Int> = []
    private var seen: Set<Int> = []
    private var finals: [Int: String] = [:]
    private var endedAt: Double?
    private var phraseEnd: UInt64 = 0
    private var emittedAt: UInt64 = 0

    public init(clip: TestCallClip) { self.clip = clip; id = UUID().uuidString }
    public var phase: String { result != nil ? "complete" : endedAt != nil ? "waiting" : "playing" }
    public var text: String { finals.keys.sorted().compactMap { finals[$0] }.filter { !$0.isEmpty }.joined(separator: " ") }
    public var playbackEnded: Bool { endedAt != nil }

    public mutating func handle(_ event: TranscriptEvent) {
        guard result == nil else { return }
        switch event {
        case .speechStarted(let u): seen.insert(u); pending.insert(u)
        case .speechEnded(let u, let at):
            if seen.contains(u) { phraseEnd = max(phraseEnd, at) }
        case .partial(let u, let value):
            if seen.contains(u) { partial = value }
        case .final(let u, let value, _, let end, let emitted):
            guard seen.contains(u) else { return }
            finals[u] = value
            if !revising.contains(u) { pending.remove(u) }
            partial = ""
            phraseEnd = max(phraseEnd, end)
            emittedAt = max(emittedAt, emitted)
        case .revising(let u):
            // Оценка — по уточнённому тексту (R-37); задержка — по быстрому итогу, который видит ход.
            if seen.contains(u) { revising.insert(u) }
        case .discarded(let u, _):
            pending.remove(u)
            revising.remove(u)
        case .revised(let u, let value, _):
            guard seen.contains(u) else { return }
            finals[u] = value
            revising.remove(u)
            pending.remove(u)
        }
    }

    public mutating func endPlayback(at now: Double) { if endedAt == nil { endedAt = now } }

    /// Запас после конца файла позволяет VAD закрыть последнюю речь. Долгая очередь не считается успехом.
    public mutating func tick(at now: Double) {
        guard result == nil, let endedAt, now - endedAt >= 0.8 else { return }
        guard (!finals.isEmpty && pending.isEmpty) || now - endedAt >= 20 else { return }
        let problem: String? = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Звук не распознан. Проверьте источник, громкость и разрешение системного звука."
            : !pending.isEmpty ? "Не все части фразы распознаны за 20 секунд. Повторите тест." : nil
        finish(problem: problem)
    }

    public mutating func fail(_ message: String) { guard result == nil else { return }; finish(problem: message) }

    private mutating func finish(problem: String?) {
        let comparison = TranscriptComparison(reference: clip.text, recognized: text)
        let latency = phraseEnd > 0 && emittedAt >= phraseEnd ? Double(emittedAt - phraseEnd) / 1e6 : nil
        result = TestCallResult(trialID: id, clipID: clip.id, language: clip.language, reference: clip.text,
                               recognized: text, words: comparison.referenceWords, errors: comparison.errors,
                               wer: comparison.wordErrorRate * 100, latencyMs: latency, problem: problem)
    }
}
