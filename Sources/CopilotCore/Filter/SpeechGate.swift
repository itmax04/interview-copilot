@preconcurrency import CoreML
import FluidAudio
import Foundation

/// Нейросетевая проверка «в реплике есть речь» — COPILOT-05 R-02. Silero VAD (FluidAudio) оценивает закрытую реплику
/// перед распознаванием: музыка, клавиатура и шум без речи не уходят в Parakeet и не дают «Угу»/«Yeah».
///
/// Решение исполнителя (handoff COPILOT-05): Silero работает кусками по 256 мс, поэтому сегментацию оставляет
/// быстрый энергетический детектор (конец фразы не запаздывает — COPILOT-04), а Silero проверяет уже закрытую реплику.
public final class SileroSpeechGate: @unchecked Sendable {
    /// Папка установленной модели (`scripts/fetch-filter-models.py`).
    public static let modelFolder = "silero-vad-coreml"
    public static let modelFile = "silero-vad-unified-256ms-v6.2.1.mlmodelc"

    /// Реплика — речь, если хотя бы в одном куске 256 мс вероятность речи не ниже порога (подбор — eval `filter`).
    public let threshold: Float
    private let manager: VadManager
    private let lock = NSLock()

    private init(manager: VadManager, threshold: Float) {
        self.manager = manager
        self.threshold = threshold
    }

    public static func isInstalled(in modelsDirectory: URL) -> Bool {
        FileManager.default.fileExists(atPath: modelsDirectory.appendingPathComponent(modelFolder)
            .appendingPathComponent(modelFile).appendingPathComponent("coremldata.bin").path)
    }

    public static func load(from modelsDirectory: URL, threshold: Float = 0.5) throws -> SileroSpeechGate {
        let url = modelsDirectory.appendingPathComponent(modelFolder).appendingPathComponent(modelFile)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        let model = try MLModel(contentsOf: url, configuration: configuration)
        return SileroSpeechGate(manager: VadManager(config: VadConfig(computeUnits: .cpuAndNeuralEngine), vadModel: model),
                                threshold: threshold)
    }

    /// Наибольшая вероятность речи по кускам 256 мс (0…1). Синхронно — вызывается из очереди распознавания.
    public func speechProbability(_ samples: [Float]) -> Float {
        speechStats(samples).max
    }

    /// Наибольшая вероятность и число кусков 256 мс с речью (вероятность ≥ порога).
    public func speechStats(_ samples: [Float]) -> (max: Float, speechChunks: Int) {
        let probabilities = chunkProbabilities(samples)
        return (probabilities.max() ?? 0, probabilities.filter { $0 >= threshold }.count)
    }

    /// Речь — если её хотя бы 2 куска (≈ 0,5 с) или один кусок с уверенностью ≥ 0,9. Одиночный всплеск шума
    /// (живой лог 2026-10-23: короткие отрезки 0,66–1,2 с превращались в «Дякую!») — не речь.
    public func isSpeech(_ samples: [Float]) -> Bool {
        let stats = speechStats(samples)
        return stats.speechChunks >= 2 || stats.max >= 0.9
    }

    private func chunkProbabilities(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        let manager = self.manager
        let done = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable { var value: [Float] = [1] }
        let box = Box()
        Task.detached(priority: .userInitiated) {
            // Ошибка модели не должна терять вопрос: считаем, что речь есть.
            if let results = try? await manager.process(samples) { box.value = results.map(\.probability) }
            done.signal()
        }
        done.wait()
        return box.value
    }
}
