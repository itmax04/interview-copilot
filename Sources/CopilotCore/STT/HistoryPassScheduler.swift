import Foundation

/// Фоновый проход Whisper по звуку вопроса для истории (COPILOT-15 R-07).
///
/// Правила: одна задача в работе; новая заменяет ожидающую; задача, прождавшая в очереди дольше `maxAge`, не
/// запускается; пока идёт новая реплика (`isBusy`), задача ждёт — процессор нужен следующему вопросу. Результат
/// идёт только в `apply` (память интервью, история, отчёт): подсказку и ход он не меняет и не задерживает.
public final class HistoryPassScheduler: @unchecked Sendable {
    public struct Job: Sendable {
        public var turn: Int
        public var audio: QuestionAudio
        public var language: String?
        /// Текст вопроса, который сейчас лежит в памяти и истории: именно его заменяет результат.
        public var oldText: String
        public var submittedAt: Double
    }

    public struct Stats: Sendable, Equatable {
        public var started = 0
        public var applied = 0
        public var replaced = 0
        public var droppedStale = 0
        public var maxInFlight = 0
    }

    private let maxAge: Double
    private let now: @Sendable () -> Double
    private let isBusy: @Sendable () -> Bool
    private let run: @Sendable (Job) -> Transcription?
    private let apply: @Sendable (Job, Transcription) -> Void
    private let queue = DispatchQueue(label: "com.itmax04.interviewcopilot.stt-history", qos: .utility)
    private let lock = NSLock()
    private var inFlight = false
    private var waiting: Job?
    private var generation = 0
    private var _stats = Stats()

    public var stats: Stats { lock.withLock { _stats } }

    /// - Parameters:
    ///   - now: секунды (монотонные); по умолчанию `DispatchTime`.
    ///   - run: блокирующий прогон Whisper; nil — оставить текст как есть.
    public init(maxAge: Double = 8,
                now: @escaping @Sendable () -> Double = { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 },
                isBusy: @escaping @Sendable () -> Bool,
                run: @escaping @Sendable (Job) -> Transcription?,
                apply: @escaping @Sendable (Job, Transcription) -> Void) {
        self.maxAge = maxAge
        self.now = now
        self.isBusy = isBusy
        self.run = run
        self.apply = apply
    }

    public func submit(turn: Int, audio: QuestionAudio, language: String?, oldText: String) {
        let job = Job(turn: turn, audio: audio, language: language, oldText: oldText, submittedAt: now())
        lock.withLock {
            if let old = waiting {
                _stats.replaced += 1
                Log.metrics.notice("whisper_history turn=\(old.turn) outcome=replaced")
            }
            waiting = job
        }
        pump()
    }

    /// Освободился процессор (реплика закончилась): ожидающая задача может стартовать.
    public func kick() { pump() }

    /// Пауза или конец сессии: ожидающая задача и результат той, что в работе, отбрасываются.
    public func reset() {
        lock.withLock {
            generation += 1
            waiting = nil
        }
    }

    private func pump() {
        let started: (Job, Int)? = lock.withLock {
            guard !inFlight, let job = waiting else { return nil }
            let waited = now() - job.submittedAt
            if waited > maxAge {
                waiting = nil
                _stats.droppedStale += 1
                Log.metrics.notice("whisper_history turn=\(job.turn) outcome=stale waited_ms=\(Int(waited * 1000))")
                return nil
            }
            guard !isBusy() else { return nil }
            waiting = nil
            inFlight = true
            _stats.started += 1
            _stats.maxInFlight = max(_stats.maxInFlight, 1)
            return (job, generation)
        }
        guard let (job, gen) = started else { return }
        queue.async { [self] in
            let began = now()
            let result = run(job)
            let ms = Int((now() - began) * 1000)
            let current = lock.withLock { () -> Bool in
                inFlight = false
                return gen == generation
            }
            if let result, current, !result.text.isEmpty, result.text != job.oldText {
                lock.withLock { _stats.applied += 1 }
                Log.metrics.notice("whisper_history turn=\(job.turn) outcome=applied audio_ms=\(Int(job.audio.seconds * 1000)) decode_ms=\(ms)")
                apply(job, result)
            } else {
                Log.metrics.notice("whisper_history turn=\(job.turn) outcome=\(current ? "unchanged" : "reset", privacy: .public) decode_ms=\(ms)")
            }
            pump()
        }
    }
}
