import FluidAudio
import Foundation
import NaturalLanguage

/// Локальный Parakeet v3 через Core ML. В очередь STT передаётся синхронный адаптер;
/// сама модель работает в async-задаче, главный поток приложения не блокируется.
public final class ParakeetEngine: SpeechRecognizer, @unchecked Sendable {
    public var nativeMultilingual: Bool { true }
    private let manager: AsrManager
    private let inferenceLock = NSLock()
    private let cancellationLock = NSLock()
    private var activeTask: Task<Void, Never>?

    private init(manager: AsrManager) { self.manager = manager }

    public static func load(from directory: URL) async throws -> ParakeetEngine {
        AppLogger.minimumLevel = .warning
        AppLogger.mirrorsToConsole = false
        // Установленные модели уже проверены установщиком. Во время слушания сеть не нужна.
        ModelHub.offlineMode = true
        let models = try await AsrModels.load(from: directory, version: .v3)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        return ParakeetEngine(manager: manager)
    }

    public func cancel() { cancellationLock.withLock { activeTask?.cancel() } }

    public func detectLanguage(_ samples: [Float]) throws -> (String, [String: Float]) {
        // StreamingTranscriber использует nativeMultilingual и не вызывает отдельный детектор.
        throw ASRError.processingFailed("Parakeet определяет язык вместе с текстом")
    }

    public func transcribe(_ input: [Float], language: String?, prompt: String?, reducedContext: Bool) throws -> Transcription {
        inferenceLock.lock()
        defer { inferenceLock.unlock() }
        let seconds = Double(input.count) / 16_000
        guard EnergyVAD.rmsDB(input[...]) >= WhisperEngine.silenceDB else {
            return Transcription(text: "", language: language ?? "en", languageProbabilities: [:],
                                 audioSeconds: seconds, elapsedMs: 0, noSpeechProbability: 1)
        }
        let audio = WhisperEngine.normalized(input)
        let result = BlockingResult<Transcription>()
        let manager = self.manager
        let task = Task.detached(priority: .userInitiated) {
            do {
                try Task.checkCancellation()
                var state = try TdtDecoderState()
                let started = Date()
                // Не ограничиваем алфавит: в русской/украинской фразе могут быть английские термины.
                let recognized = try await manager.transcribe(audio, decoderState: &state)
                try Task.checkCancellation()
                let text = recognized.text.trimmingCharacters(in: .whitespacesAndNewlines)
                result.finish(.success(Transcription(text: text,
                    language: language ?? Self.language(of: text), languageProbabilities: [:],
                    audioSeconds: seconds, elapsedMs: Date().timeIntervalSince(started) * 1000,
                    noSpeechProbability: text.isEmpty ? 1 : 0,
                    averageTokenProbability: recognized.confidence)))
            } catch { result.finish(.failure(error)) }
        }
        cancellationLock.withLock { activeTask = task }
        defer { cancellationLock.withLock { activeTask = nil } }
        return try result.wait()
    }

    /// Только метка для базы вопросов; она не заставляет модель менять язык текста.
    static func language(of text: String) -> String {
        let detector = NLLanguageRecognizer()
        detector.languageConstraints = [.ukrainian, .russian, .english]
        detector.processString(text)
        return detector.dominantLanguage?.rawValue ?? "en"
    }
}

private final class BlockingResult<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let ready = DispatchSemaphore(value: 0)
    private var result: Result<Value, Error>?
    func finish(_ value: Result<Value, Error>) {
        lock.withLock { result = value }
        ready.signal()
    }
    func wait() throws -> Value {
        ready.wait()
        return try lock.withLock { try result!.get() }
    }
}
