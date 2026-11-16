@preconcurrency import AVFoundation
import Foundation

/// Определяет, говорит ли владелец в микрофон — R-02. Звук микрофона не расшифровывается,
/// не сохраняется и никуда не отправляется: в памяти только текущий кадр для VAD.
public final class MicActivityDetector: @unchecked Sendable {
    /// Tap микрофона с перезапуском при смене устройства ввода (`MicrophoneTap`).
    private lazy var tap = MicrophoneTap(label: "mic VAD", onBuffer: { [weak self] buffer in
        self?.handle(buffer)
    }, onInterruption: { [weak self] in
        self?.resetSpeaking()
    })
    private let converter = PCMConverter()
    /// Порог для микрофона выше, чем для звука собеседника: фон комнаты, клавиатура и вентилятор не должны считаться
    /// речью владельца (иначе автоответ блокируется, S-07). Голос у ноутбучного микрофона — примерно −35…−15 dBFS.
    public static let config: EnergyVAD.Config = {
        var c = EnergyVAD.Config()
        c.minSpeechDB = -36 // эхо динамиков у микрофона — около −40…−44 dBFS (замер P-08)
        c.marginDB = 12
        c.attackFrames = 4
        c.hangoverMs = 400
        return c
    }()
    private var vad = EnergyVAD(config: MicActivityDetector.config)
    private var peakDB: Float = -120
    private let lock = NSLock()
    private var speaking = false
    private let onChange: @Sendable (Bool) -> Void
    /// Звук микрофона 16 кГц моно для расшифровки речи владельца на созвоне (COPILOT-05 R-07); nil — только VAD.
    private let samplesLock = NSLock()
    private var _onSamples: (@Sendable ([Float]) -> Void)?
    public var onSamples: (@Sendable ([Float]) -> Void)? {
        get { samplesLock.withLock { _onSamples } }
        set { samplesLock.withLock { _onSamples = newValue } }
    }

    public init(onChange: @escaping @Sendable (Bool) -> Void = { _ in }) {
        self.onChange = onChange
    }

    public var isOwnerSpeaking: Bool { lock.withLock { speaking } }

    /// Пиковый уровень микрофона с прошлого вызова, dBFS (диагностика; звук не сохраняется).
    public func takePeakDB() -> Float {
        lock.withLock {
            let v = peakDB
            peakDB = -120
            return v
        }
    }

    public func start() throws {
        guard Permissions.microphone == .granted else { return }
        // Состояние «работает» берём у tap, а не храним у себя: после отказа перезапуска tap остановлен сам,
        // и свой флаг заставил бы следующий start() молча вернуться на мёртвом движке (COPILOT-13 M2).
        guard !tap.isRunning else { return }
        guard try tap.start() else { return }
        Log.audio.info("mic VAD started")
    }

    public func stop() {
        tap.stop()
        lock.withLock {
            speaking = false
            vad.reset()
        }
        Log.audio.info("mic VAD stopped")
    }

    /// Устройство ввода сменилось посреди речи: конца речи со старого устройства уже не будет — сообщаем его сами.
    private func resetSpeaking() {
        let wasSpeaking = lock.withLock { () -> Bool in
            defer { speaking = false; vad.reset() }
            return speaking
        }
        if wasSpeaking { onChange(false) }
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        let samples = converter.convert(buffer)
        let changes = lock.withLock { () -> [Bool] in
            let c = vad.process(samples)
            peakDB = max(peakDB, EnergyVAD.rmsDB(samples[...]))
            if let last = c.last { speaking = last }
            return c
        }
        for c in changes { onChange(c) }
        if let onSamples, !samples.isEmpty { onSamples(samples) }
    }
}
