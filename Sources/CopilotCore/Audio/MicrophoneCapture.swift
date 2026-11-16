@preconcurrency import AVFoundation
import Foundation

/// Захват микрофона Mac как источника речи «собеседника» — режим самопроверки (запрос владельца 2026-10-07):
/// владелец сам задаёт вопросы голосом, без созвона. Выход — 16 кГц моно, как у системного звука; на диск не пишется (R-04).
public final class MicrophoneCapture: @unchecked Sendable {
    /// Tap микрофона с перезапуском при смене устройства ввода (`MicrophoneTap`).
    private lazy var tap = MicrophoneTap(label: "microphone capture", onBuffer: { [weak self] buffer in
        guard let self else { return }
        let samples = self.converter.convert(buffer)
        if !samples.isEmpty { self.onSamples(samples) }
    })
    private let converter = PCMConverter()
    private let onSamples: @Sendable ([Float]) -> Void

    public init(onSamples: @escaping @Sendable ([Float]) -> Void) {
        self.onSamples = onSamples
    }

    /// Берётся у tap: после отказа перезапуска движка он остановлен сам, и следующий `start()` должен запуститься (M2).
    public var isRunning: Bool { tap.isRunning }

    public func start() throws {
        guard Permissions.microphone == .granted else { throw AudioCaptureError.failed(L10n.t("Нет разрешения на микрофон")) }
        guard !isRunning else { return }
        guard try tap.start() else { throw AudioCaptureError.failed(L10n.t("Микрофон недоступен")) }
        Log.audio.info("capture started: Microphone")
    }

    public func stop() {
        tap.stop()
        Log.audio.info("microphone capture stopped")
    }
}
