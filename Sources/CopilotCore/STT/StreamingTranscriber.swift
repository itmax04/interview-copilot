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
    /// После `final` этой реплики придёт уточнённый текст (R-37). Приходит до `final`.
    case revising(utterance: Int)
    /// Уточнённый итог (украинский — Whisper `uk`, R-35/R-37). Ход и подсказка уже запущены по быстрому `final`.
    case revised(utterance: Int, text: String, language: String)
    /// Реплика без текста (шум, тишина, ошибка распознавания): её итога ждать не нужно (R-38).
    case discarded(utterance: Int, phraseEnd: UInt64)
    /// Реплика сказана не владельцем (отпечаток голоса, COPILOT-05 R-03): вместо `final`, показывается серым.
    case foreignVoice(utterance: Int, text: String, similarity: Float, phraseEnd: UInt64)
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
        /// Итог использует полный контекст; частичный текст остаётся быстрым.
        public var finalReducedContext = false
        /// С какой длины реплики определять язык, с.
        public var languageDetectAfter: Double = 1.2
        /// Уточнять язык, пока уверенность ниже порога, каждые `languageRefineStep` с звука, но не дольше `languageRefineUntil`.
        public var languageConfidence: Float = 0.9
        public var languageRefineStep: Double = 1.0
        public var languageRefineUntil: Double = 8
        /// Закреплять язык разговора после двух уверенных реплик и пропускать детектор (~1,5 с на medium, не прерывается).
        /// Собеседование обычно идёт на одном языке; при смене языка уверенность падает и закрепление снимается.
        /// Если язык известен заранее, надёжнее выбрать его в меню Language.
        public var stickyLanguage = true
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
    /// Уточнение итога (Whisper) идёт параллельно: следующая реплика не ждёт его (R-37).
    private let revisionWork = DispatchQueue(label: "com.itmax04.interviewcopilot.stt-revision", qos: .userInitiated)
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
    private var lowConfidenceStreak = 0
    private var partialBusy = false
    /// Что сейчас распознаётся: прерывать можно только частичный прогон, итог чужой реплики — нельзя.
    private var runningPartial = false
    /// Номер «эпохи»: пауза увеличивает его, и итоги, поставленные в очередь до паузы, не выдаются (S-08).
    private var epoch = 0
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
    /// Подсказка распознаванию (initial prompt whisper) для языка: словарь из базы вопросов и предыдущие реплики.
    /// Помогает на терминах и именах при сжатом звуке созвона (H-4, решение владельца — вариант 1).
    public func setPromptProvider(_ provider: (@Sendable (String) -> String?)?) {
        lock.withLock { promptProvider = provider }
    }

    private var promptProvider: (@Sendable (String) -> String?)?

    /// Детектор для источника «Микрофон Mac» (COPILOT-05): шум комнаты у микрофона −46…−58 dBFS, голос рядом −25…−30 dBFS.
    /// Порог −62 dBFS (тихий звук Meet) открывал реплики на шуме, и Whisper превращал их в слова («Дякую!»).
    public static let microphoneVAD: EnergyVAD.Config = {
        var c = Config().vad
        c.minSpeechDB = -45
        return c
    }()

    /// Сменить детектор речи (источник звука сменился): незаконченная реплика отбрасывается.
    public func setVADConfig(_ vadConfig: EnergyVAD.Config) {
        lock.withLock {
            vad = EnergyVAD(config: vadConfig)
            utteranceStart = nil
        }
    }

    /// Проверка «в реплике есть речь» перед распознаванием итога (COPILOT-05 R-02); nil — без проверки.
    public func setSpeechGate(_ gate: (@Sendable ([Float]) -> Bool)?) {
        lock.withLock { speechGate = gate }
    }

    private var speechGate: (@Sendable ([Float]) -> Bool)?

    /// Проверка голоса владельца (COPILOT-05 R-03): сходство с отпечатком и решение; nil — реплика не проверяется
    /// (короче 1 с или ошибка модели). Без проверки — nil.
    public typealias VoiceCheck = @Sendable ([Float]) -> (similarity: Float, accepted: Bool)?

    public func setVoiceGate(_ check: VoiceCheck?) {
        lock.withLock { voiceGate = check }
    }

    private var voiceGate: VoiceCheck?
    private var recentFinals: [(language: String, text: String)] = []

    func prompt(for language: String?) -> String? {
        guard let language else { return nil }
        let (provider, recent) = lock.withLock { (promptProvider, recentFinals) }
        var parts: [String] = []
        if let base = provider?(language), !base.isEmpty { parts.append(base) }
        // Предыдущие реплики в подсказку не добавляются: на сжатом звуке whisper начинал их повторять (замер P-12).
        _ = recent
        let joined = parts.joined(separator: " ")
        return joined.isEmpty ? nil : String(joined.suffix(600))
    }

    public func setLanguage(_ code: String?) {
        lock.withLock {
            language = code
            sessionLanguage = nil
            languageStreak = nil
        }
    }

    /// Пауза (S-08): незавершённая реплика отбрасывается, ничего не распознаётся.
    public func setPaused(_ value: Bool) {
        let cancel = lock.withLock { () -> Bool in
            paused = value
            utteranceStart = nil
            vad.reset()
            if value { epoch += 1 }
            return value
        }
        if cancel {
            recognizer.cancel()
            recognizer.cancelRevision()
        }
    }

    private struct FinalRequest: Sendable {
        let utterance: Int
        let audio: [Float]
        let language: String?
        let languageWasExplicit: Bool
        let usesSessionLanguage: Bool
        let phraseEnd: UInt64
        let epoch: Int
    }

    /// Новые сэмплы собеседника. Буфер пополняет вызывающий код.
    public func process(_ samples: [Float]) {
        let sr = Double(buffer.sampleRate)
        var events: [TranscriptEvent] = []
        var finals: [FinalRequest] = []
        var partialRequest: (Int, Int64, Int64, Bool)?
        let now = DispatchTime.now().uptimeNanoseconds

        lock.lock()
        if paused { lock.unlock(); return }
        let end = buffer.endPosition
        let blockStart = end - Int64(samples.count)
        func finish(at boundary: Int64, from start: Int64) {
            let lag = Double(end - boundary) / sr + Double(config.vad.hangoverMs) / 1000
            let lagNs = UInt64(max(0, lag) * 1_000_000_000)
            let phraseEnd = now > lagNs ? now - lagNs : now
            // Сохраняем звук и язык сейчас: очередь может ждать дольше срока кольцевого буфера.
            finals.append(FinalRequest(utterance: utterance, audio: buffer.read(from: start, to: boundary),
                                       language: language ?? utteranceLanguage, languageWasExplicit: language != nil,
                                       usesSessionLanguage: utteranceUsesSessionLanguage,
                                       phraseEnd: phraseEnd, epoch: epoch))
            events.append(.speechEnded(utterance: utterance, at: phraseEnd))
        }
        for change in vad.processEvents(samples) {
            let boundary = blockStart + Int64(change.sampleOffset)
            if change.isSpeech {
                utterance += 1
                utteranceStart = max(buffer.startPosition, boundary - Int64(config.preRoll * sr))
                utteranceUsesSessionLanguage = language == nil && sessionLanguage != nil
                utteranceLanguage = language ?? sessionLanguage
                utteranceLanguageConfidence = utteranceLanguage == nil ? 0 : 1
                languageDetectedAtLength = 0
                utteranceSlavic = false
                if utteranceUsesSessionLanguage, sessionLanguage == "uk" || sessionLanguage == "ru" {
                    utteranceSlavic = true
                    utteranceLanguageConfidence = 0.5
                }
                lastPartialAt = boundary
                events.append(.speechStarted(utterance: utterance))
            } else if let start = utteranceStart {
                finish(at: boundary, from: start)
                utteranceStart = nil
            }
        }
        if let start = utteranceStart {
            let length = Double(end - start) / sr
            if length >= config.maxUtterance {
                finish(at: end, from: start)
                utterance += 1
                utteranceStart = end
                lastPartialAt = end
                events.append(.speechStarted(utterance: utterance))
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

        for event in events { onEvent(event) }
        if !finals.isEmpty, lock.withLock({ runningPartial }) { recognizer.cancel() }
        for request in finals {
            work.async { [weak self] in self?.runFinal(request) }
        }
        if let (u, start, end, needsLanguage) = partialRequest {
            work.async { [weak self] in self?.runPartial(utterance: u, from: start, to: end, detectLanguage: needsLanguage) }
        }
    }

    private func currentLanguage(for u: Int) -> String? {
        lock.withLock { u == utterance ? utteranceLanguage : nil }
    }

    private func runPartial(utterance u: Int, from start: Int64, to end: Int64, detectLanguage: Bool) {
        lock.withLock { runningPartial = true }
        defer { lock.withLock { partialBusy = false; runningPartial = false } }
        // Реплика уже закрыта — частичный текст не нужен.
        guard lock.withLock({ u == utterance && utteranceStart != nil }) else { return }
        let audio = buffer.read(from: start, to: end)
        if recognizer.nativeMultilingual {
            let specified = lock.withLock { language }
            guard let result = try? recognizer.transcribe(audio, language: specified, prompt: nil, reducedContext: true),
                  !isClosed(u), !result.text.isEmpty else { return }
            lock.withLock {
                guard u == utterance else { return }
                utteranceLanguage = result.language
                utteranceLanguageConfidence = 1
            }
            onEvent(.partial(utterance: u, text: result.text))
            return
        }
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
            guard let r = try? recognizer.transcribe(audio, language: lang, prompt: prompt(for: lang), reducedContext: true) else { return }
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

    private func runFinal(_ request: FinalRequest) {
        let u = request.utterance
        let scheduledEpoch = request.epoch
        let phraseEnd = request.phraseEnd
        guard lock.withLock({ epoch == scheduledEpoch && !paused }) else { return }
        let audio = request.audio
        guard !audio.isEmpty else {
            onEvent(.discarded(utterance: u, phraseEnd: phraseEnd))
            return
        }
        // COPILOT-05 R-02: нейросетевая проверка — шум без речи не распознаётся и не становится репликой.
        if let gate = lock.withLock({ speechGate }), !gate(audio) {
            Log.metrics.notice("filtered reason=vad utt=\(u) audio_ms=\(audio.count / 16)")
            onEvent(.discarded(utterance: u, phraseEnd: phraseEnd))
            return
        }
        var lang = recognizer.nativeMultilingual && !request.languageWasExplicit ? nil : request.language
        if lang == nil && !recognizer.nativeMultilingual {
            // Короткая реплика: язык не успели определить во время речи.
            if let known = lock.withLock({ lastLanguage }) {
                lang = known // короткая реплика — язык прошлой, без лишних прогонов
            } else if Double(audio.count) / Double(buffer.sampleRate) >= 1.0, let r = resolveLanguage(audio, skipDetector: false) {
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
            let result = try recognizer.transcribe(audio, language: lang, prompt: prompt(for: lang), reducedContext: config.finalReducedContext)
            let seconds = Double(audio.count) / Double(buffer.sampleRate)
            // Выдумки Whisper на тишине и шуме («Дякую!», «Спасибо за просмотр») — как отброшенный шум (COPILOT-05).
            if HallucinationFilter.isLikely(result.text, audioSeconds: seconds) {
                Log.metrics.notice("filtered reason=hallucination utt=\(u) audio_ms=\(Int(seconds * 1000))")
                onEvent(.discarded(utterance: u, phraseEnd: phraseEnd))
                return
            }
            lock.withLock {
                lastLanguage = result.language
                guard language == nil, u == utterance || utteranceStart == nil else { return }
                if request.usesSessionLanguage {
                    // Две длинные реплики подряд с низкой уверенностью — возможно, собеседник сменил язык: снова определяем.
                    if seconds >= 1.5 && result.averageTokenProbability < 0.7 {
                        lowConfidenceStreak += 1
                        if lowConfidenceStreak >= 1 {
                            sessionLanguage = nil
                            languageStreak = nil
                            lowConfidenceStreak = 0
                        }
                    } else {
                        lowConfidenceStreak = 0
                    }
                } else if seconds >= 1.5 && result.averageTokenProbability >= 0.75 {
                    let count = languageStreak?.code == result.language ? (languageStreak?.count ?? 0) + 1 : 1
                    languageStreak = (result.language, count)
                    // Язык разговора — после двух уверенных реплик подряд. Для uk/ru он только отменяет детектор
                    // (сравнение uk/ru остаётся): иначе в смешанном разговоре украинские фразы шли на русском (замер P-12).
                    if count >= 2 && config.stickyLanguage { sessionLanguage = result.language }
                }
            }
            // Тишина и шум: whisper иногда «слышит» речь там, где её нет.
            guard !result.text.isEmpty, result.noSpeechProbability < 0.8 else {
                // Без этого события определение хода ждало бы итог шума до следующей фразы (R-38).
                onEvent(.discarded(utterance: u, phraseEnd: phraseEnd))
                return
            }
            guard lock.withLock({ epoch == scheduledEpoch && !paused }) else { return }
            // R-03: чужой голос — серой строкой, без хода и подсказки.
            if let check = lock.withLock({ voiceGate }), let verdict = check(audio) {
                guard verdict.accepted else {
                    Log.metrics.notice("filtered reason=voice utt=\(u) similarity=\(verdict.similarity, format: .fixed(precision: 2)) audio_ms=\(Int(seconds * 1000))")
                    onEvent(.foreignVoice(utterance: u, text: result.text, similarity: verdict.similarity, phraseEnd: phraseEnd))
                    return
                }
                // Сходство принятых реплик — чтобы видеть обе стороны порога на живом голосе.
                Log.metrics.notice("voice_ok utt=\(u) similarity=\(verdict.similarity, format: .fixed(precision: 2)) audio_ms=\(Int(seconds * 1000))")
            }
            lock.withLock {
                recentFinals.append((result.language, result.text))
                if recentFinals.count > 6 { recentFinals.removeFirst() }
            }
            let emitted = DispatchTime.now().uptimeNanoseconds
            Log.metrics.notice("transcript_final utt=\(u) lang=\(result.language, privacy: .public) audio_ms=\(Int(result.audioSeconds * 1000)) stt_ms=\(Int(result.elapsedMs)) phrase_end_to_final_ms=\(Int((emitted - phraseEnd) / 1_000_000))")
            // Двухэтапный итог (R-37): быстрый текст сразу — ход и подсказка не ждут; уточнённый — следом.
            let revise = recognizer.revisionNeeded(result, language: lang)
            if revise { onEvent(.revising(utterance: u)) }
            onEvent(.final(utterance: u, text: result.text, language: result.language, phraseEnd: phraseEnd, emittedAt: emitted))
            if revise { scheduleRevision(utterance: u, audio: audio, language: lang, first: result, epoch: scheduledEpoch, phraseEnd: phraseEnd) }
        } catch {
            Log.stt.error("final transcription failed: \(String(describing: error), privacy: .public)")
            onEvent(.discarded(utterance: u, phraseEnd: phraseEnd))
        }
    }

    /// Уточнение итога в отдельной очереди. При ошибке или паузе — исходный текст, чтобы ожидающие не зависли.
    private func scheduleRevision(utterance u: Int, audio: [Float], language: String?, first: Transcription, epoch scheduledEpoch: Int,
                                  phraseEnd: UInt64) {
        revisionWork.async { [weak self] in
            guard let self else { return }
            var revised = first
            if self.lock.withLock({ self.epoch == scheduledEpoch && !self.paused }),
               let r = try? self.recognizer.revise(audio, language: HybridRecognizer.revisionLanguage(language: language, text: first.text),
                                                   prompt: self.prompt(for: language)), !r.text.isEmpty {
                revised = r
            }
            let ms = Int((DispatchTime.now().uptimeNanoseconds - phraseEnd) / 1_000_000)
            Log.metrics.notice("transcript_revised utt=\(u) lang=\(revised.language, privacy: .public) changed=\(revised.text != first.text) phrase_end_to_revised_ms=\(ms)")
            self.onEvent(.revised(utterance: u, text: revised.text, language: revised.language))
        }
    }
}
