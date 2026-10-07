import Foundation

/// События распознавания речи собеседника (R-03).
public enum TranscriptEvent: Sendable, Equatable {
    /// Собеседник начал говорить (новая реплика).
    case speechStarted(utterance: Int)
    /// Собеседник замолчал (VAD); `at` — момент конца речи (`DispatchTime.uptimeNanoseconds`). Текст придёт в `final`.
    case speechEnded(utterance: Int, at: UInt64)
    /// Промежуточный текст текущей реплики (обновляется, пока человек говорит).
    case partial(utterance: Int, text: String)
    /// Итоговый текст реплики после паузы. `phraseEnd` — момент окончания речи, `emittedAt` — момент выдачи текста
    /// (оба — `DispatchTime.uptimeNanoseconds`); разница — метрика AC-01.
    case final(utterance: Int, text: String, language: String, phraseEnd: UInt64, emittedAt: UInt64)
}

/// Потоковое распознавание: VAD режет поток собеседника на реплики, пока человек говорит — частичный текст,
/// после паузы — итоговый (R-03). Звук только в памяти (R-04).
///
/// Язык: если задан — используется он; если Auto — определяется во время речи (с 1,2 с реплики).
/// Детектор whisper small путает украинский с русским (замер P-04: uk-фраза → ru 0,70–0,83), поэтому при выборе
/// между uk и ru фрагмент распознаётся на обоих языках и сравнивается средняя вероятность токенов. На коротком
/// звуке (≈2 с) сравнение тоже ошибается (живой замер P-05: 0,29 против 0,67 не в пользу верного uk), а с 3,5 с —
/// стабильно верно; поэтому сравнение повторяется по мере роста реплики (до 8 с) и решает самое длинное.
/// При почти равных вероятностях (< 0,02) берётся язык прошлой реплики. Уточнение прерывается, как только
/// фраза закончилась: итог распознаётся с уже известным языком (ADR-0001, AC-01).
public final class StreamingTranscriber: @unchecked Sendable {
    public struct Config: Sendable {
        /// Как часто обновлять частичный текст, с.
        public var partialInterval: Double = 0.8
        /// С какой длины реплики определять язык, с.
        public var languageDetectAfter: Double = 1.2
        /// Уточнять язык, пока уверенность ниже порога, каждые `languageRefineStep` с звука, но не дольше `languageRefineUntil`.
        public var languageConfidence: Float = 0.9
        public var languageRefineStep: Double = 1.0
        public var languageRefineUntil: Double = 8
        /// При разнице вероятностей uk/ru меньше этой — берётся язык прошлой реплики.
        public var ukRuTie: Float = 0.02
        /// Сколько звука брать до начала речи (VAD срабатывает с задержкой «атаки»), с.
        public var preRoll: Double = 0.3
        /// Предельная длина реплики: whisper работает окнами по 30 с, буфер — 30 с (R-04).
        public var maxUtterance: Double = 25
        /// VAD собеседника: звук Meet бывает очень тихим (живой созвон H-4: речь −47…−53 dBFS при фоне −85…−90),
        /// поэтому абсолютный порог ниже, чем по умолчанию, а основную работу делает порог «шум + 10 дБ».
        public var vad: EnergyVAD.Config = {
            var c = EnergyVAD.Config()
            c.minSpeechDB = -62
            c.hangoverMs = 350
            return c
        }()

        public init() {}
    }

    private let recognizer: SpeechRecognizer
    private let config: Config
    private let onEvent: @Sendable (TranscriptEvent) -> Void
    private let buffer: AudioRingBuffer
    private let work = DispatchQueue(label: "com.itmax04.interviewcopilot.stt", qos: .userInitiated)
    private let lock = NSLock()

    // Состояние под lock.
    private var vad: EnergyVAD
    private var utterance = 0
    private var utteranceStart: Int64?
    private var language: String?           // настройка: nil = Auto
    private var utteranceLanguage: String?   // язык текущей реплики
    private var utteranceLanguageConfidence: Float = 0
    private var languageDetectedAtLength: Double = 0
    /// Текущая реплика славянская (детектор уже отработал) — дальше сравниваем только uk и ru, без детектора.
    private var utteranceSlavic = false
    private var lastLanguage: String?
    /// Язык разговора: после двух уверенных реплик подряд на одном языке определение языка пропускается
    /// (на модели medium детектор занимает ~1,5 с и задерживает итог), пока уверенность распознавания не упадёт.
    private var sessionLanguage: String?
    private var languageStreak: (code: String, count: Int)?
    private var utteranceUsesSessionLanguage = false
    private var partialBusy = false
    private var lastPartialAt: Int64 = 0
    private var paused = false

    public init(recognizer: SpeechRecognizer, buffer: AudioRingBuffer, config: Config = Config(),
                onEvent: @escaping @Sendable (TranscriptEvent) -> Void) {
        self.recognizer = recognizer
        self.buffer = buffer
        self.config = config
        self.onEvent = onEvent
        self.vad = EnergyVAD(config: config.vad)
    }

    /// Язык из настроек (R-03): "uk" / "ru" / "en" или nil — Auto.
    public func setLanguage(_ code: String?) {
        lock.withLock {
            language = code
            sessionLanguage = nil
            languageStreak = nil
        }
    }

    /// Пауза (S-08): незавершённая реплика отбрасывается, ничего не распознаётся.
    public func setPaused(_ value: Bool) {
        lock.withLock {
            paused = value
            utteranceStart = nil
            vad.reset()
        }
        if value { recognizer.cancel() }
    }

    /// Новые сэмплы собеседника. Вызывается из очереди захвата; буфер пополняет вызывающий код.
    public func process(_ samples: [Float]) {
        let sr = Double(buffer.sampleRate)
        var startedUtterance: Int?
        var finalRange: (Int, Int64, Int64)?
        var partialRequest: (Int, Int64, Int64, Bool)?
        let now = DispatchTime.now().uptimeNanoseconds

        lock.lock()
        if paused {
            lock.unlock()
            return
        }
        let end = buffer.endPosition
        for change in vad.process(samples) {
            if change {
                utterance += 1
                utteranceStart = max(buffer.startPosition, end - Int64(samples.count) - Int64(config.preRoll * sr))
                utteranceUsesSessionLanguage = language == nil && sessionLanguage != nil
                utteranceLanguage = language ?? sessionLanguage
                utteranceLanguageConfidence = utteranceLanguage == nil ? 0 : 1
                languageDetectedAtLength = 0
                utteranceSlavic = false
                lastPartialAt = end
                startedUtterance = utterance
            } else if let start = utteranceStart {
                finalRange = (utterance, start, end)
                utteranceStart = nil
            }
        }
        if let start = utteranceStart {
            let length = Double(end - start) / sr
            if length >= config.maxUtterance {
                // Слишком длинная реплика — закрываем и сразу начинаем следующую.
                finalRange = (utterance, start, end)
                utterance += 1
                utteranceStart = end
                startedUtterance = utterance
            } else if !partialBusy, Double(end - lastPartialAt) / sr >= config.partialInterval {
                partialBusy = true
                lastPartialAt = end
                let needsLanguage = language == nil && length >= config.languageDetectAfter
                    && (utteranceLanguage == nil
                        || (utteranceLanguageConfidence < config.languageConfidence
                            && length <= config.languageRefineUntil
                            && length - languageDetectedAtLength >= config.languageRefineStep))
                partialRequest = (utterance, start, end, needsLanguage)
            }
        }
        lock.unlock()

        if let u = startedUtterance { onEvent(.speechStarted(utterance: u)) }
        if let (u, start, end) = finalRange {
            // Итог важнее частичного: прерываем текущий частичный прогон.
            recognizer.cancel()
            let hangoverNs = UInt64(config.vad.hangoverMs) * 1_000_000
            let phraseEnd = now > hangoverNs ? now - hangoverNs : now
            onEvent(.speechEnded(utterance: u, at: phraseEnd))
            work.async { [weak self] in self?.runFinal(utterance: u, from: start, to: end, phraseEnd: phraseEnd) }
        }
        if let (u, start, end, needsLanguage) = partialRequest {
            work.async { [weak self] in self?.runPartial(utterance: u, from: start, to: end, detectLanguage: needsLanguage) }
        }
    }

    private func currentLanguage(for u: Int) -> String? {
        lock.withLock { u == utterance ? utteranceLanguage : nil }
    }

    private func runPartial(utterance u: Int, from start: Int64, to end: Int64, detectLanguage: Bool) {
        defer { lock.withLock { partialBusy = false } }
        // Реплика уже закрыта — частичный текст не нужен.
        guard lock.withLock({ u == utterance && utteranceStart != nil }) else { return }
        let audio = buffer.read(from: start, to: end)
        var resolved: Transcription?
        let slavicKnown = lock.withLock { utteranceSlavic }
        if detectLanguage, let r = resolveLanguage(audio, skipDetector: slavicKnown, isCancelled: { [weak self] in
            self?.isClosed(u) ?? true
        }) {
            resolved = r.transcription
            lock.withLock {
                guard u == utterance else { return }
                languageDetectedAtLength = Double(audio.count) / Double(buffer.sampleRate)
                if let delta = r.ukMinusRu {
                    // uk/ru: решает самое длинное сравнение; продолжаем уточнять до languageRefineUntil.
                    utteranceSlavic = true
                    utteranceLanguage = abs(delta) < config.ukRuTie ? (lastLanguage ?? r.code) : r.code
                    utteranceLanguageConfidence = 0.5
                } else {
                    utteranceLanguage = r.code
                    utteranceLanguageConfidence = r.confidence
                }
            }
            if let resolvedText = resolved, resolvedText.language != currentLanguage(for: u) { resolved = nil }
        }
        guard !isClosed(u) else { return }
        let lang = currentLanguage(for: u) ?? lock.withLock({ lastLanguage })
        guard let lang else { return } // язык ещё не известен — ждём определения
        let result: Transcription
        if let resolved, resolved.language == lang {
            result = resolved
        } else {
            guard let r = try? recognizer.transcribe(audio, language: lang, prompt: nil, reducedContext: true) else { return }
            result = r
        }
        guard lock.withLock({ u == utterance && utteranceStart != nil }), !result.text.isEmpty else { return }
        onEvent(.partial(utterance: u, text: result.text))
    }

    struct LanguageGuess {
        var code: String
        var confidence: Float
        /// Для выбора uk/ru: средняя вероятность токенов uk минус ru; nil — язык не славянский.
        var ukMinusRu: Float?
        var transcription: Transcription?
    }

    /// Реплика закрыта (собеседник замолчал) или началась новая — частичные прогоны больше не нужны.
    private func isClosed(_ u: Int) -> Bool {
        lock.withLock { u != utterance || utteranceStart == nil }
    }

    /// Язык фрагмента: детектор whisper, а при выборе между uk и ru — сравнение уверенности распознавания на обоих.
    /// `skipDetector` — реплика уже известна как славянская: только сравнение uk/ru (быстрее, прерывается `cancel`).
    func resolveLanguage(_ audio: [Float], skipDetector: Bool, isCancelled: () -> Bool = { false }) -> LanguageGuess? {
        let code: String
        let probs: [String: Float]
        if skipDetector {
            (code, probs) = ("uk", ["uk": 0.5, "ru": 0.5])
        } else {
            guard let detected = try? recognizer.detectLanguage(audio) else { return nil }
            (code, probs) = detected
        }
        guard !isCancelled() else { return nil }
        let slavic = (probs["uk"] ?? 0) + (probs["ru"] ?? 0)
        guard code == "uk" || code == "ru" || slavic > (probs["en"] ?? 0) else {
            return LanguageGuess(code: code, confidence: probs[code] ?? 0, ukMinusRu: nil, transcription: nil)
        }
        guard let uk = try? recognizer.transcribe(audio, language: "uk", prompt: nil, reducedContext: true), !isCancelled(),
              let ru = try? recognizer.transcribe(audio, language: "ru", prompt: nil, reducedContext: true)
        else { return nil }
        let winner = uk.averageTokenProbability >= ru.averageTokenProbability ? uk : ru
        let margin = abs(uk.averageTokenProbability - ru.averageTokenProbability)
        Log.stt.info("lang resolve audio_ms=\(audio.count / 16) detector=\(code, privacy: .public) p_uk=\(probs["uk"] ?? 0, format: .fixed(precision: 2)) p_ru=\(probs["ru"] ?? 0, format: .fixed(precision: 2)) tok_uk=\(uk.averageTokenProbability, format: .fixed(precision: 3)) tok_ru=\(ru.averageTokenProbability, format: .fixed(precision: 3)) -> \(winner.language, privacy: .public)")
        return LanguageGuess(code: winner.language, confidence: margin >= 0.05 ? 1 : 0.5,
                             ukMinusRu: uk.averageTokenProbability - ru.averageTokenProbability, transcription: winner)
    }

    private func runFinal(utterance u: Int, from start: Int64, to end: Int64, phraseEnd: UInt64) {
        let audio = buffer.read(from: start, to: end)
        guard !audio.isEmpty else { return }
        var lang = lock.withLock { () -> String? in
            if language != nil { return language }
            return u == utterance ? utteranceLanguage : nil
        }
        if lang == nil {
            // Короткая реплика: язык не успели определить во время речи.
            if Double(audio.count) / Double(buffer.sampleRate) >= 1.0, let r = resolveLanguage(audio, skipDetector: false) {
                if let delta = r.ukMinusRu, abs(delta) < config.ukRuTie {
                    lang = lock.withLock { lastLanguage } ?? r.code
                } else {
                    lang = r.code
                }
            } else {
                lang = lock.withLock { lastLanguage }
            }
        }
        do {
            let result = try recognizer.transcribe(audio, language: lang, prompt: nil, reducedContext: true)
            let seconds = Double(audio.count) / Double(buffer.sampleRate)
            lock.withLock {
                lastLanguage = result.language
                guard language == nil, u == utterance || utteranceStart == nil else { return }
                if utteranceUsesSessionLanguage {
                    // Низкая уверенность на длинной реплике — возможно, собеседник сменил язык: снова определяем.
                    if seconds >= 1.5 && result.averageTokenProbability < 0.55 {
                        sessionLanguage = nil
                        languageStreak = nil
                    }
                } else if seconds >= 1.5 && result.averageTokenProbability >= 0.75 {
                    let count = languageStreak?.code == result.language ? (languageStreak?.count ?? 0) + 1 : 1
                    languageStreak = (result.language, count)
                    if count >= 2 { sessionLanguage = result.language }
                }
            }
            // Тишина и шум: whisper иногда «слышит» речь там, где её нет.
            guard !result.text.isEmpty, result.noSpeechProbability < 0.8 else { return }
            let emitted = DispatchTime.now().uptimeNanoseconds
            Log.metrics.notice("transcript_final utt=\(u) lang=\(result.language, privacy: .public) audio_ms=\(Int(result.audioSeconds * 1000)) stt_ms=\(Int(result.elapsedMs)) phrase_end_to_final_ms=\(Int((emitted - phraseEnd) / 1_000_000))")
            onEvent(.final(utterance: u, text: result.text, language: result.language, phraseEnd: phraseEnd, emittedAt: emitted))
        } catch {
            Log.stt.error("final transcription failed: \(String(describing: error), privacy: .public)")
        }
    }
}
