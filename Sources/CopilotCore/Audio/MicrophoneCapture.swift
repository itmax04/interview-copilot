@preconcurrency import AVFoundation
import Foundation

/// Захват микрофона Mac как источника речи «собеседника» — режим самопроверки (запрос владельца 2026-10-07):
/// владелец сам задаёт вопросы голосом, без созвона. Выход — 16 кГц моно, как у системного звука; на диск не пишется (R-04).
public final class MicrophoneCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let converter = PCMConverter()
    private let onSamples: @Sendable ([Float]) -> Void
    private let lock = NSLock()
    private var running = false

    public init(onSamples: @escaping @Sendable ([Float]) -> Void) {
        self.onSamples = onSamples
    }

    public var isRunning: Bool { lock.withLock { running } }

    public func start() throws {
        guard Permissions.microphone == .granted else { throw AudioCaptureError.failed(L10n.t("Нет разрешения на микрофон")) }
        guard !isRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw AudioCaptureError.failed(L10n.t("Микрофон недоступен")) }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let samples = self.converter.convert(buffer)
            if !samples.isEmpty { self.onSamples(samples) }
        }
        engine.prepare()
        try engine.start()
        lock.withLock { running = true }
        Log.audio.info("capture started: Microphone")
    }

    public func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.withLock { running = false }
        Log.audio.info("microphone capture stopped")
    }
}
