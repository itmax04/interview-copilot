import Foundation

/// Результат повторного распознавания вопроса целиком (COPILOT-15 R-01).
public struct QuestionRedecode: Sendable, Equatable {
    public var text: String
    public var language: String
    public var source: QuestionAudio.Source
    public var audioMs: Int
    public var decodeMs: Int
}

/// Один проход распознавателя по звуку всего вопроса вместо склейки текстов фраз (R-01, R-05, R-12).
/// Бюджет по умолчанию 2 с: не уложились или ошибка — nil, ход идёт по тексту фраз, пишется `redecode_failed`.
/// Фазовый конвейер `StreamingTranscriber` не затрагивается; движок один, прогон встаёт в его очередь.
public final class QuestionRedecoder: @unchecked Sendable {
    public struct Config: Sendable {
        public var budget: Double = 2
        /// Запасной вариант B (COPILOT-15 R-14, выключен): после Parakeet вопрос распознаётся Whisper turbo целиком и его
        /// текст заменяет текст Parakeet; бюджет выше (+2,2–2,4 с на M1). Включается одной строкой после живой проверки.
        public var waitsForWhisper = false
        public static let whisperBudget: Double = 6
        public init(waitsForWhisper: Bool = false, whisperBudget: Double = Config.whisperBudget) {
            self.waitsForWhisper = waitsForWhisper
            if waitsForWhisper { budget = whisperBudget }
        }
    }

    private let recognizer: SpeechRecognizer
    private let config: Config
    public var waitsForWhisper: Bool { config.waitsForWhisper }
    private let queue = DispatchQueue(label: "com.itmax04.interviewcopilot.stt-redecode", qos: .userInitiated)
    /// Отдельная очередь для таймера бюджета: общий пул GCD может быть занят блокирующими прогонами.
    private let timer = DispatchQueue(label: "com.itmax04.interviewcopilot.stt-redecode-budget", qos: .userInitiated)

    public init(recognizer: SpeechRecognizer, config: Config = Config()) {
        self.recognizer = recognizer
        self.config = config
    }

    /// `language` — язык фраз (nil для мультиязычного движка). `turn` и `provisionalWords` — только для метрики.
    /// `waits: false` — спекулятивный черновик: ожидание Whisper не применяется, бюджет обычный (COPILOT-17 R-07).
    public func run(_ audio: QuestionAudio, language: String?, turn: Int, provisionalWords: Int, waits: Bool = true) async -> QuestionRedecode? {
        let waitsForWhisper = config.waitsForWhisper && waits
        let budget = (config.waitsForWhisper && !waits) ? Config().budget : config.budget
        let started = DispatchTime.now().uptimeNanoseconds
        let audioMs = Int(audio.seconds * 1000)
        let usedWhisper = Flag()
        let outcome: Result<Transcription, Error>? = await withCheckedContinuation { continuation in
            let once = Once(continuation)
            queue.async { [recognizer] in
                var attempt = 0
                while true {
                    do {
                        var r = try recognizer.transcribe(audio.samples, language: language, prompt: nil, reducedContext: false)
                        if waitsForWhisper, recognizer.revisionNeeded(r, language: language),
                           let second = try? recognizer.revise(audio.samples, language: HybridRecognizer.revisionLanguage(language: language, text: r.text), prompt: nil) {
                            r = second
                            usedWhisper.set()
                        }
                        once.resume(.success(r))
                        return
                    } catch {
                        attempt += 1
                        // Чужая отмена частичного прогона на общем движке: повторяем, как итог фразы.
                        guard StreamingTranscriber.isCancellation(error), attempt < 3 else {
                            once.resume(.failure(error))
                            return
                        }
                    }
                }
            }
            timer.asyncAfter(deadline: .now() + budget) { once.resume(nil) }
        }
        let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
        if waitsForWhisper {
            let used = outcome != nil && usedWhisper.value ? "whisper" : "parakeet"
            Log.metrics.notice("hint_wait_whisper turn=\(turn) waited_ms=\(elapsedMs) used=\(used, privacy: .public)")
        }
        switch outcome {
        case .success(let t) where !t.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            let text = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
            Log.metrics.notice("redecode turn=\(turn) audio_ms=\(audioMs) decode_ms=\(elapsedMs) source=\(audio.source.rawValue, privacy: .public) words_provisional=\(provisionalWords) words_final=\(text.split { $0.isWhitespace }.count)")
            return QuestionRedecode(text: text, language: t.language, source: audio.source, audioMs: audioMs, decodeMs: elapsedMs)
        case .success:
            Log.metrics.notice("redecode_failed turn=\(turn) reason=empty audio_ms=\(audioMs) elapsed_ms=\(elapsedMs)")
        case .failure:
            Log.metrics.notice("redecode_failed turn=\(turn) reason=error audio_ms=\(audioMs) elapsed_ms=\(elapsedMs)")
        case nil:
            Log.metrics.notice("redecode_failed turn=\(turn) reason=budget audio_ms=\(audioMs) elapsed_ms=\(elapsedMs)")
        }
        return nil
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var on = false
        func set() { lock.withLock { on = true } }
        var value: Bool { lock.withLock { on } }
    }

    /// Продолжение, которое возобновляется один раз: результат прогона и таймер бюджета соревнуются.
    private final class Once: @unchecked Sendable {
        private var continuation: CheckedContinuation<Result<Transcription, Error>?, Never>?
        private let lock = NSLock()
        init(_ continuation: CheckedContinuation<Result<Transcription, Error>?, Never>) { self.continuation = continuation }
        func resume(_ value: Result<Transcription, Error>?) {
            let c = lock.withLock { () -> CheckedContinuation<Result<Transcription, Error>?, Never>? in
                defer { continuation = nil }
                return continuation
            }
            c?.resume(returning: value)
        }
    }
}
