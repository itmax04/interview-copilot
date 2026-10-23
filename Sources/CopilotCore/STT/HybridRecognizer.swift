import Foundation

/// Parakeet + Whisper для украинского (COPILOT-03, R-35). Parakeet не умеет закреплять язык, и украинская речь
/// у него сползает в русскую. Предварительный текст — Parakeet (быстро); итог украинской фразы — Whisper
/// с языком `uk`: так в тексте остаются украинские слова и буквы. Русский и английский итог — Parakeet.
public final class HybridRecognizer: SpeechRecognizer, @unchecked Sendable {
    public var nativeMultilingual: Bool { true }
    private let primary: SpeechRecognizer
    private let loadVerifier: @Sendable () throws -> SpeechRecognizer
    private let lock = NSLock()
    private var verifier: SpeechRecognizer?
    private var verifierFailed = false

    /// Whisper загружается при первой украинской фразе: без украинского памяти он не занимает.
    public init(primary: SpeechRecognizer, loadVerifier: @escaping @Sendable () throws -> SpeechRecognizer) {
        self.primary = primary
        self.loadVerifier = loadVerifier
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

    public func transcribeFinal(_ samples: [Float], language: String?, prompt: String?, reducedContext: Bool) throws -> Transcription {
        let first = try primary.transcribe(samples, language: language, prompt: prompt, reducedContext: reducedContext)
        guard !first.text.isEmpty, Self.needsUkrainian(language: language, text: first.text),
              let whisper = verifierInstance() else { return first }
        // Полный контекст: на урезанном turbo зацикливается (ADR-0001, P-04).
        guard let second = try? whisper.transcribe(samples, language: "uk", prompt: prompt, reducedContext: false),
              !second.text.isEmpty, second.noSpeechProbability < 0.8 else { return first }
        var result = second
        result.language = "uk"
        result.elapsedMs = first.elapsedMs + second.elapsedMs
        Log.stt.info("hybrid uk final parakeet_ms=\(Int(first.elapsedMs)) whisper_ms=\(Int(second.elapsedMs))")
        return result
    }

    public func detectLanguage(_ samples: [Float]) throws -> (String, [String: Float]) {
        try primary.detectLanguage(samples)
    }

    public func cancel() {
        primary.cancel()
        lock.withLock { verifier }?.cancel()
    }

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
