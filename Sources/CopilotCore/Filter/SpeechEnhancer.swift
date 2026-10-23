@preconcurrency import CoreML
import FluidAudio
import Foundation

/// Шумоподавление реплики микрофона — COPILOT-05 R-04. LocalVQE v1.3 (FluidAudio, Apache-2.0): шум и реверберация
/// убираются из закрытой реплики перед распознаванием и проверкой голоса. Без опорного сигнала — только шумоподавление;
/// эхоподавление по звуку звонка (потоковый режим 16 мс) — этап 4.
public final class SpeechEnhancer: @unchecked Sendable {
    public static let modelFolder = "localvqe-coreml"
    public static let config = LocalVqeConfig(variant: .v13, chunk: .batch256ms, computeUnits: .cpuOnly)

    private let manager: LocalVqeManager
    private let lock = NSLock()

    private init(manager: LocalVqeManager) { self.manager = manager }

    public static func isInstalled(in modelsDirectory: URL) -> Bool {
        let file = ModelNames.LocalVQE.modelFile(variant: config.variant, chunk: config.chunk)
        return FileManager.default.fileExists(atPath: modelsDirectory.appendingPathComponent(modelFolder)
            .appendingPathComponent(file).appendingPathComponent("coremldata.bin").path)
    }

    public static func load(from modelsDirectory: URL) throws -> SpeechEnhancer {
        SpeechEnhancer(manager: try LocalVqeManager(config: config, modelDirectory: modelsDirectory.appendingPathComponent(modelFolder)))
    }

    /// Очищенная реплика той же длины; nil — ошибка модели (тогда распознаётся исходный звук).
    public func enhance(_ samples: [Float]) -> [Float]? {
        guard !samples.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        let manager = self.manager
        let done = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable { var value: [Float]? }
        let box = Box()
        Task.detached(priority: .userInitiated) {
            box.value = try? await manager.process(mic: samples)
            done.signal()
        }
        done.wait()
        guard let out = box.value, out.count == samples.count else { return nil }
        return out
    }
}

/// Состояние шумоподавления для очереди распознавания: модель и «включено» (режим микрофона и настройка).
public final class EnhancerBox: @unchecked Sendable {
    public struct State: Sendable {
        public var enhancer: SpeechEnhancer?
        public var active = false
        public init() {}
    }

    private let lock = NSLock()
    private var state = State()

    public init() {}

    public func update(_ change: (inout State) -> Void) { lock.withLock { change(&state) } }
    public var current: State { lock.withLock { state } }

    public func enhance(_ samples: [Float]) -> [Float]? {
        let s = current
        guard s.active, let enhancer = s.enhancer else { return nil }
        return enhancer.enhance(samples)
    }
}
