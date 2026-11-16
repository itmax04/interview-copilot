@preconcurrency import AVFoundation
import Foundation

/// Вход микрофона через `AVAudioEngine`: общий код для `MicActivityDetector` и `MicrophoneCapture`.
///
/// Две вещи, которых не было, пока каждый класс ставил tap сам:
/// - при ошибке запуска движка tap снимается — повторная установка tap на ту же шину бросает исключение AVFoundation,
///   и следующий `start()` ронял приложение;
/// - смена устройства ввода (подключили наушники или AirPods посреди созвона) останавливает движок и присылает
///   `AVAudioEngineConfigurationChange`. Без перезапуска tap со старым форматом молчал до конца сессии, а «владелец
///   говорит» застывало в последнем значении — при `true` автоответы блокировались (S-07).
final class MicrophoneTap: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let label: String
    private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void
    /// Движок остановлен сменой устройства: вызывающий сбрасывает своё состояние (VAD, «говорит»).
    private let onInterruption: @Sendable () -> Void
    private let lock = NSLock()
    private var running = false
    private var observer: NSObjectProtocol?
    /// Номер запуска (растёт в `start`/`stop`) и номер цепочки перезапуска (растёт с каждым уведомлением). Отложенная
    /// попытка сверяет оба: иначе повтор из старой цепочки пережил бы `stop()` + `start()` и остановил здоровый движок,
    /// а два уведомления подряд вели бы две цепочки сразу.
    private var session = 0
    private var chain = 0
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
    }

    var isRunning: Bool { lock.withLock { running } }

    /// Запуск. `false` — входного устройства нет (формат без частоты); ошибка — движок не запустился.
    @discardableResult
    func start() throws -> Bool {
        guard !isRunning else { return true }
        guard try startEngine() else { return false }
        let session = lock.withLock { () -> Int in
            self.session += 1
            return self.session
        }
        let observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                                              queue: nil) { [weak self] _ in
            // Уведомление приходит из потока движка: его методы отсюда вызывать нельзя — уходим на главный поток,
            // там же, где `start`/`stop`.
            DispatchQueue.main.async { self?.configurationChanged(session: session) }
        }
        lock.withLock {
            running = true
            self.observer = observer
        }
        return true
    }

    func stop() {
        let observer = lock.withLock { () -> NSObjectProtocol? in
            guard running else { return nil }
            running = false
            session += 1
            defer { self.observer = nil }
            return self.observer
        }
        guard let observer else { return }
        NotificationCenter.default.removeObserver(observer)
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func startEngine() throws -> Bool {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }
        input.removeTap(onBus: 0)
        let onBuffer = self.onBuffer
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in onBuffer(buffer) }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        return true
    }

    private func configurationChanged(session: Int) {
        let chain = lock.withLock { () -> Int? in
            guard running, self.session == session else { return nil }
            self.chain += 1
            return self.chain
        }
        guard let chain else { return }
        onInterruption()
        restart(attempt: 1, session: session, chain: chain)
    }

    private func restart(attempt: Int, session: Int, chain: Int) {
        guard lock.withLock({ running && self.session == session && self.chain == chain }) else { return }
        engine.stop()
        let started = (try? startEngine()) ?? false
        if started {
            Log.audio.notice("\(self.label, privacy: .public) restarted after audio configuration change attempt=\(attempt)")
        } else if attempt < Self.restartAttempts {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.restart(attempt: attempt + 1, session: session, chain: chain)
            }
        } else {
            // Вход так и не вернулся: снимаем tap и считаем себя остановленными, чтобы следующий `start()` (новая
            // сессия, снятие паузы) попробовал заново, а не вернул «уже работает» на мёртвом движке.
            Log.audio.error("\(self.label, privacy: .public) not restarted after audio configuration change")
            stop()
        }
    }
}
