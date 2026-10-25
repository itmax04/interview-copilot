import Foundation
import whisper

public enum WhisperError: Error, CustomStringConvertible {
    case modelNotFound(String)
    case loadFailed(String)
    case inferenceFailed(Int32)
    case cancelled

    public var description: String {
        switch self {
        case .modelNotFound(let path): L10n.f("Модель не найдена: %@", path)
        case .loadFailed(let path): L10n.f("Не удалось загрузить модель: %@", path)
        case .inferenceFailed(let code): L10n.f("whisper_full вернул %@", "\(code)")
        case .cancelled: L10n.t("Распознавание отменено")
        }
    }
}

/// Результат распознавания одного фрагмента.
public struct Transcription: Sendable, Equatable {
    public var text: String
    /// Код языка (uk / ru / en).
    public var language: String
    /// Вероятности uk/ru/en при автоопределении (пусто, если язык задан явно).
    public var languageProbabilities: [String: Float]
    public var audioSeconds: Double
    public var elapsedMs: Double
    /// Вероятность «нет речи» (максимум по сегментам) — отсев шума и галлюцинаций.
    public var noSpeechProbability: Float
    /// Средняя вероятность текстовых токенов — уверенность модели в тексте (сравнение uk/ru).
    public var averageTokenProbability: Float = 0
}

/// Распознавание речи — абстракция для тестов `StreamingTranscriber` без модели.
public protocol SpeechRecognizer: AnyObject, Sendable {
    /// Мультиязычный движок распознаёт напрямую, без отдельных прогонов uk/ru.
    var nativeMultilingual: Bool { get }
    func transcribe(_ samples: [Float], language: String?, prompt: String?, reducedContext: Bool) throws -> Transcription
    func detectLanguage(_ samples: [Float]) throws -> (String, [String: Float])
    func cancel()
    /// Итоговый текст фразы. Гибрид (`HybridRecognizer`) проверяет здесь украинский итог через Whisper.
    func transcribeFinal(_ samples: [Float], language: String?, prompt: String?, reducedContext: Bool) throws -> Transcription
    /// Нужен ли уточнённый итог после быстрого (R-37). По умолчанию — нет.
    func revisionNeeded(_ first: Transcription, language: String?) -> Bool
    /// Уточнённый итог; nil — оставить быстрый.
    func revise(_ samples: [Float], language: String?, prompt: String?) throws -> Transcription?
    func cancelRevision()
}

public extension SpeechRecognizer {
    var nativeMultilingual: Bool { false }
    func transcribeFinal(_ samples: [Float], language: String?, prompt: String?, reducedContext: Bool) throws -> Transcription {
        try transcribe(samples, language: language, prompt: prompt, reducedContext: reducedContext)
    }
    func revisionNeeded(_ first: Transcription, language: String?) -> Bool { false }
    func revise(_ samples: [Float], language: String?, prompt: String?) throws -> Transcription? { nil }
    func cancelRevision() {}
}

/// Обёртка C API whisper.cpp (ADR-0001 п. 5, R-03). Один экземпляр — один контекст; вызовы сериализуются.
/// Автоопределение языка ограничено набором uk/ru/en.
public final class WhisperEngine: SpeechRecognizer, @unchecked Sendable {
    public static let supportedLanguages = ["uk", "ru", "en"]
    /// Ниже этого уровня (dBFS по всему фрагменту) речи нет.
    public static let silenceDB: Float = -68

    /// Тихий звук (созвон с тихим собеседником) поднимается до пика 0,5, но не больше чем в 40 раз (+32 дБ).
    static func normalized(_ samples: [Float]) -> [Float] {
        var peak: Float = 0
        for s in samples { peak = max(peak, abs(s)) }
        guard peak > 0, peak < 0.25 else { return samples }
        let gain = min(0.5 / peak, 40)
        return samples.map { $0 * gain }
    }

    public let modelPath: String
    private let ctx: OpaquePointer
    /// Отдельное состояние для определения языка: `audio_ctx` из урезанных прогонов хранится в основном состоянии
    /// и портит автоопределение (замер P-04: вероятности «плыли» между повторами).
    private let detectState: OpaquePointer
    private let lock = NSLock()
    private let abortFlag = AbortFlag()
    public let threads: Int32

    final class AbortFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool { lock.withLock { value } }
        func set(_ v: Bool) { lock.withLock { value = v } }
    }

    public init(modelPath: String, useGPU: Bool = true, threads: Int32 = 4) throws {
        guard FileManager.default.fileExists(atPath: modelPath) else { throw WhisperError.modelNotFound(modelPath) }
        Self.silenceNativeLogs()
        var cparams = whisper_context_default_params()
        cparams.use_gpu = useGPU
        cparams.flash_attn = useGPU
        guard let ctx = whisper_init_from_file_with_params(modelPath, cparams) else {
            throw WhisperError.loadFailed(modelPath)
        }
        guard let detectState = whisper_init_state(ctx) else {
            whisper_free(ctx)
            throw WhisperError.loadFailed(modelPath)
        }
        self.ctx = ctx
        self.detectState = detectState
        self.modelPath = modelPath
        self.threads = threads
        Log.stt.info("whisper model loaded: \((modelPath as NSString).lastPathComponent, privacy: .public) gpu=\(useGPU)")
    }

    deinit {
        whisper_free_state(detectState)
        whisper_free(ctx)
    }

    /// Логи whisper.cpp/ggml не нужны в stderr приложения (и не должны содержать текст речи).
    private static let silenced: Void = {
        whisper_log_set({ _, _, _ in }, nil)
    }()

    static func silenceNativeLogs() { _ = silenced }

    /// Прервать текущее распознавание (новая фраза важнее старой частичной).
    public func cancel() { abortFlag.set(true) }

    /// Распознать фрагмент 16 кГц моно. `language`: код uk/ru/en или nil — автоопределение среди uk/ru/en.
    /// `audioContext`: 0 — полный контекст (30 с), иначе урезанный под длину звука (быстрее на коротких фразах).
    public func transcribe(_ input: [Float], language: String?, prompt: String? = nil,
                           reducedContext: Bool = true) throws -> Transcription {
        lock.lock()
        defer { lock.unlock() }
        abortFlag.set(false)
        let started = DispatchTime.now()

        // whisper требует не меньше ~1 с звука; короткие фрагменты дополняются тишиной.
        var samples = Self.normalized(input)
        let minSamples = 16_000 + 1_600
        if samples.count < minSamples { samples += [Float](repeating: 0, count: minSamples - samples.count) }
        let audioSeconds = Double(input.count) / 16_000

        // На тишине whisper выдумывает текст («you», «Повтори!», зацикленные фразы — замер P-04): не запускаем модель.
        if EnergyVAD.rmsDB(input[...]) < Self.silenceDB {
            return Transcription(text: "", language: language ?? "en", languageProbabilities: [:], audioSeconds: audioSeconds,
                                 elapsedMs: 0, noSpeechProbability: 1)
        }

        var lang = language
        var probabilities: [String: Float] = [:]
        if lang == nil {
            (lang, probabilities) = try detectLanguageLocked(samples)
        }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = threads
        params.translate = false
        params.no_context = true
        params.no_timestamps = true
        params.single_segment = false
        params.print_special = false
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.suppress_blank = true
        params.suppress_nst = true
        params.temperature = 0
        params.temperature_inc = 0 // без повторов с повышенной температурой: важнее задержка (AC-01)
        // Короткий предварительный прогон ограничен по длине. Итог не режем по эвристике
        // «8 токенов/с»: в быстрой речи и кириллице она может обрезать правильные слова.
        params.max_tokens = reducedContext ? Int32(min(220, Int(audioSeconds * 8) + 16)) : 0
        if reducedContext {
            // 1500 кадров = 30 с; берём длину звука + запас, кратно 64 (известная практика whisper.cpp stream).
            let frames = Int((Double(samples.count) / 16_000 * 50).rounded(.up)) + 64
            params.audio_ctx = Int32(min(1500, (frames + 63) / 64 * 64))
        }
        let flag = Unmanaged.passUnretained(abortFlag).toOpaque()
        params.abort_callback = { userData in
            guard let userData else { return false }
            return Unmanaged<AbortFlag>.fromOpaque(userData).takeUnretainedValue().isSet
        }
        params.abort_callback_user_data = flag

        let code: Int32 = (lang ?? "en").withCString { langPtr in
            params.language = langPtr
            if let prompt, !prompt.isEmpty {
                return prompt.withCString { promptPtr in
                    params.initial_prompt = promptPtr
                    return samples.withUnsafeBufferPointer { whisper_full(ctx, params, $0.baseAddress, Int32($0.count)) }
                }
            }
            return samples.withUnsafeBufferPointer { whisper_full(ctx, params, $0.baseAddress, Int32($0.count)) }
        }
        if abortFlag.isSet { throw WhisperError.cancelled }
        guard code == 0 else { throw WhisperError.inferenceFailed(code) }

        var text = ""
        var noSpeech: Float = 0
        var pSum: Float = 0
        var pCount = 0
        let eot = whisper_token_eot(ctx)
        for i in 0..<whisper_full_n_segments(ctx) {
            if let cstr = whisper_full_get_segment_text(ctx, i) { text += String(cString: cstr) }
            noSpeech = max(noSpeech, whisper_full_get_segment_no_speech_prob(ctx, i))
            for j in 0..<whisper_full_n_tokens(ctx, i) {
                // Служебные токены (язык, таймкоды, EOT) имеют id ≥ EOT.
                guard whisper_full_get_token_id(ctx, i, j) < eot else { continue }
                pSum += whisper_full_get_token_p(ctx, i, j)
                pCount += 1
            }
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e6
        return Transcription(text: Self.clean(text), language: lang ?? "en", languageProbabilities: probabilities,
                             audioSeconds: audioSeconds, elapsedMs: elapsed, noSpeechProbability: noSpeech,
                             averageTokenProbability: pCount > 0 ? pSum / Float(pCount) : 0)
    }

    /// Автоопределение языка с выбором лучшего из uk/ru/en (S-11). Полный контекст энкодера.
    public func detectLanguage(_ input: [Float]) throws -> (String, [String: Float]) {
        lock.lock()
        defer { lock.unlock() }
        var samples = Self.normalized(input)
        if samples.count < 17_600 { samples += [Float](repeating: 0, count: 17_600 - samples.count) }
        return try detectLanguageLocked(samples)
    }

    private func detectLanguageLocked(_ samples: [Float]) throws -> (String, [String: Float]) {
        let rc = samples.withUnsafeBufferPointer {
            whisper_pcm_to_mel_with_state(ctx, detectState, $0.baseAddress, Int32($0.count), threads)
        }
        guard rc == 0 else { throw WhisperError.inferenceFailed(rc) }
        var probs = [Float](repeating: 0, count: Int(whisper_lang_max_id()) + 1)
        let top = whisper_lang_auto_detect_with_state(ctx, detectState, 0, threads, &probs)
        guard top >= 0 else { throw WhisperError.inferenceFailed(top) }
        var result: [String: Float] = [:]
        for code in Self.supportedLanguages {
            let id = whisper_lang_id(code)
            if id >= 0 { result[code] = probs[Int(id)] }
        }
        let best = result.max { $0.value < $1.value }?.key ?? "en"
        return (best, result)
    }

    /// Убирает пробелы по краям, служебные вставки вроде «[музыка]», «(applause)» и зацикленные повторы фраз.
    static func clean(_ text: String) -> String {
        var t = text.replacingOccurrences(of: #"\[[^\]]*\]|\([^)]*\)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        t = collapseRepeats(t.trimmingCharacters(in: .whitespacesAndNewlines))
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Фраза из 1–8 слов, повторённая 3+ раза подряд, оставляется один раз.
    static func collapseRepeats(_ text: String) -> String {
        var words = text.split(separator: " ").map(String.init)
        guard words.count >= 6 else { return text }
        func norm(_ w: String) -> String { w.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        var n = 1
        while n <= 8 {
            var i = 0
            var changed = false
            while i + n * 3 <= words.count {
                let unit = words[i..<(i + n)].map(norm)
                var reps = 1
                while i + n * (reps + 1) <= words.count,
                      words[(i + n * reps)..<(i + n * (reps + 1))].map(norm) == unit { reps += 1 }
                if reps >= 3 {
                    words.removeSubrange((i + n)..<(i + n * reps))
                    changed = true
                }
                i += 1
            }
            if !changed { n += 1 }
        }
        return words.joined(separator: " ")
    }
}
