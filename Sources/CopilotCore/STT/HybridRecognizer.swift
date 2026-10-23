import Foundation

/// Parakeet + Whisper для украинского (COPILOT-03, R-35). Parakeet не умеет закреплять язык, и украинская речь
/// у него сползает в русскую. Предварительный текст — Parakeet (быстро); итог украинской фразы — Whisper
/// с языком `uk`: так в тексте остаются украинские слова и буквы. Русский и английский итог — Parakeet.
public final class HybridRecognizer: SpeechRecognizer, @unchecked Sendable {
    public var nativeMultilingual: Bool { true }
    private let primary: SpeechRecognizer
    private let loadVerifier: @Sendable () throws -> SpeechRecognizer
    /// Уточнять и русский/английский итог (термины: «поуст Griskl» → PostgreSQL), а не только украинский (R-37).
    public let reviseAllLanguages: Bool
    private let lock = NSLock()
    private var verifier: SpeechRecognizer?
    private var verifierFailed = false

    /// Whisper загружается при первой украинской фразе: без украинского памяти он не занимает.
    public init(primary: SpeechRecognizer, reviseAllLanguages: Bool = false,
                loadVerifier: @escaping @Sendable () throws -> SpeechRecognizer) {
        self.primary = primary
        self.reviseAllLanguages = reviseAllLanguages
        self.loadVerifier = loadVerifier
    }

    /// Язык уточнения: выбранный в меню; иначе по буквам быстрого текста.
    public static func revisionLanguage(language: String?, text: String) -> String {
        if let language { return language }
        if hasUkrainianLetters(text) { return "uk" }
        return text.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) } ? "ru" : "en"
    }

    /// Буквы, которых нет в русском: і, ї, є, ґ.
    public static func hasUkrainianLetters(_ text: String) -> Bool {
        text.lowercased().contains { "іїєґ".contains($0) }
    }

    /// Украинский итог: язык выбран явно или Parakeet оставил украинские буквы (фраза сползает в русский частично).
    public static func needsUkrainian(language: String?, text: String) -> Bool {
        language == "uk" || (language == nil && hasUkrainianLetters(text))
    }

    public func transcribe(_ samples: [Float], language: String?, prompt: String?, reducedContext: Bool) throws -> Transcription {
        try primary.transcribe(samples, language: language, prompt: prompt, reducedContext: reducedContext)
    }

    /// Итог одним вызовом (copilot-eval): быстрый текст и, если нужно, сразу уточнённый.
    public func transcribeFinal(_ samples: [Float], language: String?, prompt: String?, reducedContext: Bool) throws -> Transcription {
        let first = try primary.transcribe(samples, language: language, prompt: prompt, reducedContext: reducedContext)
        guard revisionNeeded(first, language: language),
              var second = try revise(samples, language: Self.revisionLanguage(language: language, text: first.text), prompt: prompt)
        else { return first }
        second.elapsedMs += first.elapsedMs
        return second
    }

    /// В приложении (R-37) быстрый текст Parakeet уходит в ход и подсказку сразу, украинский уточняется следом.
    public func revisionNeeded(_ first: Transcription, language: String?) -> Bool {
        !first.text.isEmpty && (reviseAllLanguages || Self.needsUkrainian(language: language, text: first.text))
    }

    public func revise(_ samples: [Float], language: String?, prompt: String?) throws -> Transcription? {
        guard let whisper = verifierInstance() else { return nil }
        // Полный контекст: на урезанном turbo зацикливается (ADR-0001, P-04).
        // Язык закреплён: для украинского это и есть защита от сползания в русский (R-35).
        let target = language ?? "uk"
        guard let second = try? whisper.transcribe(samples, language: target, prompt: prompt, reducedContext: false),
              !second.text.isEmpty, second.noSpeechProbability < 0.8 else { return nil }
        var result = second
        result.language = target
        Log.stt.info("hybrid revision lang=\(target, privacy: .public) whisper_ms=\(Int(second.elapsedMs))")
        return result
    }

    public func cancelRevision() { lock.withLock { verifier }?.cancel() }

    public func detectLanguage(_ samples: [Float]) throws -> (String, [String: Float]) {
        try primary.detectLanguage(samples)
    }

    /// Прерывает только быстрый прогон: уточнение прошлой реплики идёт своим ходом (отменяет `cancelRevision`).
    public func cancel() { primary.cancel() }

    private func verifierInstance() -> SpeechRecognizer? {
        lock.lock()
        defer { lock.unlock() }
        if let verifier { return verifier }
        guard !verifierFailed else { return nil }
        do {
            let v = try loadVerifier()
            verifier = v
            return v
        } catch {
            verifierFailed = true
            Log.stt.error("hybrid: whisper not loaded: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
