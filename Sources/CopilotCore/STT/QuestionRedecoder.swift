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
        public init() {}
    }

    private let recognizer: SpeechRecognizer
    private let config: Config
    private let queue = DispatchQueue(label: "com.itmax04.interviewcopilot.stt-redecode", qos: .userInitiated)
    /// Отдельная очередь для таймера бюджета: общий пул GCD может быть занят блокирующими прогонами.
    private let timer = DispatchQueue(label: "com.itmax04.interviewcopilot.stt-redecode-budget", qos: .userInitiated)

    public init(recognizer: SpeechRecognizer, config: Config = Config()) {
        self.recognizer = recognizer
        self.config = config
    }

    /// `language` — язык фраз (nil для мультиязычного движка). `turn` и `provisionalWords` — только для метрики.
    public func run(_ audio: QuestionAudio, language: String?, turn: Int, provisionalWords: Int) async -> QuestionRedecode? {
        let started = DispatchTime.now().uptimeNanoseconds
        let audioMs = Int(audio.seconds * 1000)
        let outcome: Result<Transcription, Error>? = await withCheckedContinuation { continuation in
            let once = Once(continuation)
            queue.async { [recognizer] in
                var attempt = 0
                while true {
                    do {
                        let r = try recognizer.transcribe(audio.samples, language: language, prompt: nil, reducedContext: false)
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
            timer.asyncAfter(deadline: .now() + config.budget) { once.resume(nil) }
        }
        let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
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
