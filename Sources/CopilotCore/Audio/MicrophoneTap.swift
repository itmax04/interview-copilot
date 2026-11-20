@preconcurrency import AVFoundation
import CoreAudio
import Foundation

/// Вход микрофона через `AVAudioEngine`: общий код для `MicActivityDetector` и `MicrophoneCapture`.
///
/// Две вещи, которых не было, пока каждый класс ставил tap сам:
/// - при ошибке запуска движка tap снимается — повторная установка tap на ту же шину бросает исключение AVFoundation,
///   и следующий `start()` ронял приложение;
/// - перезапуск при смене системного входа или формата движка. Без него tap мог замолчать до конца сессии,
///   а «владелец говорит» застывало в последнем значении и блокировало автоответы (S-07).
final class MicrophoneTap: @unchecked Sendable {
    @MainActor private var engine: AVAudioEngine?
    private let label: String
    private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void
    /// Движок остановлен сменой устройства: вызывающий сбрасывает своё состояние (VAD, «говорит»).
    private let onInterruption: @Sendable () -> Void
    @MainActor private(set) var isRunning = false
    private var observer: NSObjectProtocol?
    private var inputObserver: AudioObjectPropertyListenerBlock?
    @MainActor private var inputDeviceAtStart: AudioDeviceID?
    /// Отсекает уведомления старого движка и отложенные попытки после `stop()`.
    @MainActor private var generation = 0
    /// Сколько раз пробовать перезапуск: Bluetooth-гарнитура отдаёт рабочий формат входа не сразу.
    static let restartAttempts = 4

    init(label: String, onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
         onInterruption: @escaping @Sendable () -> Void = {}) {
        self.label = label
        self.onBuffer = onBuffer
        self.onInterruption = onInterruption
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let inputObserver { Self.removeDefaultInputObserver(inputObserver) }
    }

    /// Запуск. `false` — входного устройства нет (формат без частоты); ошибка — движок не запустился.
    @MainActor @discardableResult
    func start() throws -> Bool {
        guard !isRunning else { return true }
        guard try startEngine() else { return false }
        isRunning = true
        observeDefaultInput()
        defaultInputChanged()
        return true
    }

    @MainActor func stop() {
        isRunning = false
        generation += 1
        if let inputObserver {
            Self.removeDefaultInputObserver(inputObserver)
            self.inputObserver = nil
        }
        stopEngine()
    }

    @MainActor private func stopEngine() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    @MainActor private func startEngine() throws -> Bool {
        generation += 1
        let generation = self.generation
        // AVAudioEngine keeps its previous node formats after a device change.
        let device = Self.defaultInputDevice()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }
        let onBuffer = self.onBuffer
        input.installTap(onBus: 0, bufferSize: 1024, format: nil) { @Sendable buffer, _ in onBuffer(buffer) }
        let observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                                              queue: nil) { @Sendable [weak self] _ in
            // Retire the engine on the main queue, outside AVAudioEngine's notification handler.
            DispatchQueue.main.async { self?.configurationChanged(generation: generation) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            NotificationCenter.default.removeObserver(observer)
            input.removeTap(onBus: 0)
            throw error
        }
        self.engine = engine
        self.observer = observer
        inputDeviceAtStart = device
        return true
    }

    private static let systemAudioObject = AudioObjectID(kAudioObjectSystemObject)
    private static func defaultInputProperty() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultInputDevice() -> AudioDeviceID? {
        var property = defaultInputProperty()
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(systemAudioObject, &property, 0, nil, &size, &device)
        return status == noErr ? device : nil
    }

    @MainActor private func observeDefaultInput() {
        // An input change with the same format may not post AVAudioEngineConfigurationChange.
        let listener: AudioObjectPropertyListenerBlock = { @Sendable [weak self] _, _ in
            DispatchQueue.main.async { self?.defaultInputChanged() }
        }
        var property = Self.defaultInputProperty()
        let status = AudioObjectAddPropertyListenerBlock(Self.systemAudioObject, &property, .main, listener)
        if status == noErr {
            inputObserver = listener
        } else {
            Log.audio.error("could not observe default input changes status=\(status)")
        }
    }

    private static func removeDefaultInputObserver(_ observer: @escaping AudioObjectPropertyListenerBlock) {
        var property = defaultInputProperty()
        AudioObjectRemovePropertyListenerBlock(systemAudioObject, &property, .main, observer)
    }

    @MainActor private func defaultInputChanged() {
        guard let device = Self.defaultInputDevice(), device != inputDeviceAtStart else { return }
        configurationChanged(generation: generation)
    }

    @MainActor private func configurationChanged(generation: Int) {
        guard isRunning, self.generation == generation, engine != nil else { return }
        stopEngine()
        onInterruption()
        restart(attempt: 1, generation: generation)
    }

    @MainActor private func restart(attempt: Int, generation: Int) {
        guard isRunning, self.generation == generation else { return }
        let started = (try? startEngine()) ?? false
        if started {
            Log.audio.notice("\(self.label, privacy: .public) restarted after audio configuration change attempt=\(attempt)")
        } else if attempt < Self.restartAttempts {
            let nextGeneration = self.generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.restart(attempt: attempt + 1, generation: nextGeneration)
            }
        } else {
            // Вход так и не вернулся: снимаем tap и считаем себя остановленными, чтобы следующий `start()` (новая
            // сессия, снятие паузы) попробовал заново, а не вернул «уже работает» на мёртвом движке.
            Log.audio.error("\(self.label, privacy: .public) not restarted after audio configuration change")
            stop()
        }
    }
}
