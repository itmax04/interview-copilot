@preconcurrency import CoreML
import FluidAudio
import Foundation

/// Отпечаток голоса владельца — COPILOT-05 R-03. 192 числа (эмбеддинг CAM++), сравнение — косинусное сходство.
/// Хранится только на этом Mac (`…/InterviewCopilot/voice/owner.json`), звук образца не сохраняется.
public struct VoicePrint: Codable, Equatable, Sendable {
    public var embedding: [Float]
    public var createdAt: Date
    /// Сколько секунд речи вошло в образец.
    public var speechSeconds: Double
    /// Наименьшее сходство кусков образца с самим отпечатком — естественный разброс голоса на этом микрофоне.
    public var selfSimilarityMin: Float
    public var model = "campplus-coreml@321b18e"

    public init(embedding: [Float], createdAt: Date = Date(), speechSeconds: Double, selfSimilarityMin: Float = 1) {
        self.embedding = embedding
        self.createdAt = createdAt
        self.speechSeconds = speechSeconds
        self.selfSimilarityMin = selfSimilarityMin
    }

    /// Персональный порог: чуть ниже естественного разброса своего голоса, в пределах 0,55…0,85.
    /// 0,85 — на синтетических голосах свой голос принят 100%, чужие отклонены 92% (eval `voice`, AC-03);
    /// живой голос меняется сильнее синтетического, поэтому порог не выше разброса образца минус запас.
    public var recommendedThreshold: Float {
        min(Self.maxThreshold, max(Self.minThreshold, selfSimilarityMin - Self.margin))
    }

    public static let maxThreshold: Float = 0.85
    public static let minThreshold: Float = 0.55
    public static let margin: Float = 0.08

    public static var fileURL: URL { AppPaths.root.appendingPathComponent("voice/owner.json") }

    public static func load(from url: URL = fileURL) -> VoicePrint? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(VoicePrint.self, from: data)
    }

    public func save(to url: URL = fileURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: [.atomic, .completeFileProtection])
        // Голосовые данные — только для владельца (R-08 COPILOT-05).
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func delete(at url: URL = fileURL) {
        try? FileManager.default.removeItem(at: url)
    }

    enum CodingKeys: String, CodingKey { case embedding, createdAt, speechSeconds, selfSimilarityMin, model }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        embedding = try c.decode([Float].self, forKey: .embedding)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        speechSeconds = try c.decode(Double.self, forKey: .speechSeconds)
        selfSimilarityMin = (try? c.decodeIfPresent(Float.self, forKey: .selfSimilarityMin)) ?? 1
        model = (try? c.decodeIfPresent(String.self, forKey: .model)) ?? "campplus-coreml@321b18e"
    }

    public func similarity(to embedding: [Float]) -> Float {
        guard embedding.count == self.embedding.count else { return 0 }
        return zip(self.embedding, embedding).reduce(0) { $0 + $1.0 * $1.1 }
    }
}

/// CAM++ (FluidAudio) с синхронным вызовом из очереди распознавания.
public final class VoiceEmbedder: @unchecked Sendable {
    public static let modelFolder = "campplus-coreml"
    /// Короче — отпечаток ненадёжен: реплика проверяется мягче (`shortMargin`); короче `minShortSeconds` — не проверяется.
    /// Живой тест 2026-10-23: «До свидания» из видео (< 1 с) проходило без проверки и складывалось в «вопрос».
    public static let minSeconds = 1.0
    public static let minShortSeconds = 0.5
    public static let shortMargin: Float = 0.1

    private let embedder: CampPlusEmbedder
    private let lock = NSLock()

    private init(embedder: CampPlusEmbedder) { self.embedder = embedder }

    public static func isInstalled(in modelsDirectory: URL) -> Bool {
        CampPlusModels.modelsExist(at: modelsDirectory.appendingPathComponent(modelFolder))
    }

    public static func load(from modelsDirectory: URL) throws -> VoiceEmbedder {
        VoiceEmbedder(embedder: CampPlusEmbedder(models: try CampPlusModels.load(from: modelsDirectory.appendingPathComponent(modelFolder))))
    }

    /// Эмбеддинг одного отрезка 16 кГц моно (L2-нормирован). nil — ошибка модели.
    public func embed(_ samples: [Float]) -> [Float]? {
        guard !samples.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        let embedder = self.embedder
        let done = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable { var value: [Float]? }
        let box = Box()
        Task.detached(priority: .userInitiated) {
            box.value = try? await embedder.embed(audio: samples)
            done.signal()
        }
        done.wait()
        return box.value
    }

    /// Отпечаток по образцу: тишина отрезается, речь режется на окна ~4 с, эмбеддинги усредняются.
    public func makePrint(from samples: [Float]) -> VoicePrint? {
        let speech = Self.speechOnly(samples)
        let seconds = Double(speech.count) / 16_000
        guard seconds >= 5 else { return nil }
        let window = 4 * 16_000
        var parts: [[Float]] = []
        var start = 0
        while start + 16_000 * 2 <= speech.count {
            if let e = embed(Array(speech[start..<min(start + window, speech.count)])) { parts.append(e) }
            start += window
        }
        guard !parts.isEmpty else { return nil }
        var sum = [Float](repeating: 0, count: CampPlusEmbedder.embeddingDim)
        for e in parts { for i in sum.indices where i < e.count { sum[i] += e[i] } }
        let norm = max(sqrt(sum.reduce(0) { $0 + $1 * $1 }), 1e-9)
        var print = VoicePrint(embedding: sum.map { $0 / norm }, speechSeconds: seconds)
        // Калибровка: насколько каждый кусок образца похож на отпечаток (без своего вклада было бы строже — берём запас).
        print.selfSimilarityMin = parts.count > 1 ? parts.map { print.similarity(to: $0) }.min() ?? 1 : 1
        return print
    }

    /// Сходство реплики с отпечатком; nil — речи меньше `minShortSeconds` или ошибка модели (не отбрасываем).
    public func similarity(of samples: [Float], to print: VoicePrint) -> Float? {
        measure(samples, to: print)?.similarity
    }

    /// Сходство и длительность речи (для мягкого порога коротких реплик).
    public func measure(_ samples: [Float], to print: VoicePrint) -> (similarity: Float, speechSeconds: Double)? {
        let speech = Self.speechOnly(samples)
        let seconds = Double(speech.count) / 16_000
        guard seconds >= Self.minShortSeconds, let e = embed(speech) else { return nil }
        return (print.similarity(to: e), seconds)
    }

    /// Только кадры 20 мс громче −45 dBFS (паузы и тишина не размывают отпечаток).
    static func speechOnly(_ samples: [Float]) -> [Float] {
        let frame = 320
        var out: [Float] = []
        out.reserveCapacity(samples.count)
        var i = 0
        while i + frame <= samples.count {
            let slice = samples[i..<(i + frame)]
            if EnergyVAD.rmsDB(slice) > -45 { out.append(contentsOf: slice) }
            i += frame
        }
        return out
    }
}

/// Текущее состояние проверки голоса для очереди распознавания (COPILOT-05 R-03): модель, отпечаток, порог, включено ли.
/// Приложение меняет его при смене источника, режима ИИ-собеседования, настроек и образца; распознавание только читает.
public final class VoiceGateBox: @unchecked Sendable {
    public struct State: Sendable {
        public var embedder: VoiceEmbedder?
        public var print: VoicePrint?
        /// 0 — персональный порог образца.
        public var threshold: Float = 0
        public var active = false
        public init() {}
    }

    private let lock = NSLock()
    private var state = State()

    public init() {}

    public func update(_ change: (inout State) -> Void) { lock.withLock { change(&state) } }
    public var current: State { lock.withLock { state } }

    /// Порог, который действует сейчас (настройка или персональный).
    public var effectiveThreshold: Float? {
        let s = current
        guard let print = s.print else { return nil }
        return s.threshold > 0 ? s.threshold : print.recommendedThreshold
    }

    public func check(_ samples: [Float], ignoringActive: Bool = false) -> (similarity: Float, accepted: Bool)? {
        let s = current
        guard s.active || ignoringActive, let embedder = s.embedder, let print = s.print,
              let measured = embedder.measure(samples, to: print) else { return nil }
        var threshold = s.threshold > 0 ? s.threshold : print.recommendedThreshold
        if measured.speechSeconds < VoiceEmbedder.minSeconds { threshold -= VoiceEmbedder.shortMargin }
        return (measured.similarity, measured.similarity >= threshold)
    }
}
