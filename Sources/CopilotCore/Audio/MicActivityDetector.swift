@preconcurrency import AVFoundation
import Foundation

/// Определяет, говорит ли владелец в микрофон — R-02. Звук микрофона не расшифровывается,
/// не сохраняется и никуда не отправляется: в памяти только текущий кадр для VAD.
public final class MicActivityDetector: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let converter = PCMConverter()
    private var vad = EnergyVAD()
    private let lock = NSLock()
    private var speaking = false
    private var running = false
    private let onChange: @Sendable (Bool) -> Void

    public init(onChange: @escaping @Sendable (Bool) -> Void = { _ in }) {
        self.onChange = onChange
    }

    public var isOwnerSpeaking: Bool { lock.withLock { speaking } }

    public func start() throws {
        guard Permissions.microphone == .granted else { return }
        guard !lock.withLock({ running }) else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        engine.prepare()
        try engine.start()
        lock.withLock { running = true }
        Log.audio.info("mic VAD started")
    }

    public func stop() {
        guard lock.withLock({ running }) else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.withLock {
            running = false
            speaking = false
            vad.reset()
        }
        Log.audio.info("mic VAD stopped")
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        let samples = converter.convert(buffer)
        let changes = lock.withLock { () -> [Bool] in
            let c = vad.process(samples)
            if let last = c.last { speaking = last }
            return c
        }
        for c in changes { onChange(c) }
    }
}
