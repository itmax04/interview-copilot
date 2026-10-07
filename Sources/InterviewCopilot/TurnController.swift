import CopilotCore
import Foundation

/// Определение хода в приложении: события распознавания и микрофона → `TurnDetector` (R-05, S-07, S-08).
@MainActor
final class TurnController {
    private var detector: TurnDetector
    private var timer: Timer?
    /// Вызывается при завершённом ходе (дальше — поиск по базе и генерация, P-06…P-08).
    var onTurn: ((Turn) -> Void)?
    private(set) var lastTurn: Turn?

    init(thresholdMs: Int) {
        detector = TurnDetector(config: TurnDetector.Config(thresholdMs: Double(thresholdMs)))
    }

    static func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }

    func setThreshold(_ ms: Int) {
        detector.config.thresholdMs = Double(ms)
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        detector.reset()
    }

    func handle(_ event: TranscriptEvent) {
        guard timer != nil else { return } // пауза: события не копятся (S-08)
        switch event {
        case .speechStarted:
            detector.interviewerStartedSpeaking(at: Self.now())
        case .speechEnded(_, let at):
            detector.interviewerStoppedSpeaking(at: Double(at) / 1e6)
        case .partial:
            break
        case .final(_, let text, _, let phraseEnd, _):
            detector.phraseFinal(text, speechEnd: Double(phraseEnd) / 1e6)
            if let turn = detector.takeRequestedForce(at: Self.now()) { emit(turn) }
        }
    }

    func ownerSpeaking(_ speaking: Bool, at t: Double) {
        guard timer != nil else { return }
        detector.setOwnerSpeaking(speaking, at: t)
    }

    /// ⌃⌥↩ — «Answer now».
    func forceTurn() {
        if let turn = detector.force(at: Self.now()) { emit(turn) }
    }

    private func tick() {
        if let turn = detector.tick(at: Self.now()) { emit(turn) }
    }

    private func emit(_ turn: Turn) {
        lastTurn = turn
        // Метрика для AC-02/AC-03: отсчёт от конца речи (`turn_end`), текст не логируется (R-24).
        Log.metrics.notice("turn_end turn=\(turn.id) speech_end_ms=\(Int(turn.speechEndedAt)) fired_ms=\(Int(turn.firedAt)) forced=\(turn.forced) words=\(TurnDetectorWords.count(turn.text))")
        onTurn?(turn)
    }
}

enum TurnDetectorWords {
    static func count(_ text: String) -> Int { text.split { $0.isWhitespace }.count }
}
