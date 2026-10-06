import AppKit
import CopilotCore
import Observation

/// Управление слушанием: разрешения, выбор источника, захват, пауза, микрофон владельца (R-01, R-02, R-04, S-08, AC-13).
@MainActor
@Observable
final class ListeningController {
    enum Phase: Equatable {
        case noPermission
        case idle            // нет источника
        case listening
        case paused
        case error(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var source: ResolvedAudioSource = .none
    /// Уровень сигнала собеседника, dBFS (debug-индикатор P-03).
    private(set) var levelDB: Float = -120
    private(set) var ownerSpeaking = false

    /// Расшифровка собеседника (R-03): итоговые реплики и текущая частичная.
    private(set) var transcript: [TranscriptLine] = []
    private(set) var partialText: String?
    private(set) var sttStatus: String = "Модель распознавания не загружена"
    /// Последнее событие распознавания — для определения хода (P-05).
    var onTranscript: ((TranscriptEvent) -> Void)?
    /// Владелец начал/перестал говорить; время — мс монотонных часов (R-02, S-07).
    var onOwnerSpeaking: ((Bool, Double) -> Void)?

    struct TranscriptLine: Identifiable, Equatable {
        let id: Int
        let text: String
        let language: String
    }

    private var transcriber: StreamingTranscriber?
    private var loadingModel = false

    /// Буфер последних 30 с звука собеседника (R-04). Читает распознавание (P-04).
    let buffer = AudioRingBuffer(seconds: 30)
    private var capture: SystemAudioCapture?
    private var mic: MicActivityDetector?
    private let model: AppModel
    private var observers: [NSObjectProtocol] = []
    private var levelTask: Task<Void, Never>?
    private let levelMeter = LevelMeter()

    /// Вызывается при смене состояния (перестройка меню и панели).
    var onChange: (() -> Void)?

    init(model: AppModel) {
        self.model = model
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.runningAppsChanged() }
            })
        }
    }

    var listeningStatus: ListeningStatus {
        switch phase {
        case .noPermission: .noPermission
        case .listening: .listening(source: source.displayName ?? "—")
        case .paused: .paused(source: source.displayName ?? "—")
        case .idle, .error: .idle
        }
    }

    static func runningApps() -> [RunningAppInfo] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier,
                  id != Bundle.main.bundleIdentifier else { return nil }
            return RunningAppInfo(bundleID: id, name: app.localizedName ?? id)
        }
    }

    /// Запуск при старте приложения и после выдачи разрешений.
    func start() {
        guard Permissions.screenCaptureGranted else {
            setPhase(.noPermission)
            Log.audio.notice("no screen capture permission")
            return
        }
        loadRecognizer()
        startMic()
        startLevelReporting()
        Task { await applySource(restart: true) }
    }

    func togglePause() {
        switch phase {
        case .listening:
            transcriber?.setPaused(true)
            partialText = nil
            Task {
                await capture?.stop()
                mic?.stop()
                buffer.clear()
                setPhase(.paused)
            }
        case .paused:
            startMic()
            transcriber?.setPaused(false)
            Task { await applySource(restart: true) }
        default:
            break
        }
    }

    /// Смена источника из меню или настроек — без перезапуска приложения (R-01).
    func sourceSettingChanged() {
        guard phase != .paused, phase != .noPermission else { return }
        Task { await applySource(restart: false) }
    }

    private func runningAppsChanged() {
        guard phase != .paused, phase != .noPermission else { return }
        let resolved = AudioSourceResolver.resolve(model.settings.audioSource, running: Self.runningApps())
        if resolved != source { Task { await applySource(restart: false) } }
    }

    private func applySource(restart: Bool) async {
        guard Permissions.screenCaptureGranted else {
            setPhase(.noPermission)
            return
        }
        let resolved = AudioSourceResolver.resolve(model.settings.audioSource, running: Self.runningApps())
        source = resolved
        if resolved == .none {
            await capture?.stop()
            setPhase(.idle)
            return
        }
        let capture = self.capture ?? makeCapture()
        self.capture = capture
        do {
            if restart || !capture.isRunning {
                try await capture.start(resolved)
            } else {
                try await capture.switchSource(resolved)
            }
            setPhase(.listening)
        } catch AudioCaptureError.noPermission {
            setPhase(.noPermission)
        } catch {
            Log.audio.error("capture start failed: \(String(describing: error), privacy: .public)")
            setPhase(.error(String(describing: error)))
        }
    }

    /// Остановка и освобождение модели перед выходом.
    func shutdown() {
        transcriberBox.set(nil)
        transcriber?.setPaused(true)
        transcriber = nil
        mic?.stop()
        let capture = self.capture
        Task { await capture?.stop() }
    }

    /// Язык распознавания из настроек (R-03).
    func languageSettingChanged() {
        transcriber?.setLanguage(model.settings.language.whisperCode)
    }

    /// Загрузка модели whisper в фоне (≈0,5 с для small). Без модели слушание идёт, но текста нет.
    private func loadRecognizer() {
        guard transcriber == nil, !loadingModel else { return }
        let path = AppPaths.model(model.settings.whisperModel).path
        guard FileManager.default.fileExists(atPath: path) else {
            sttStatus = "Нет модели распознавания: \(model.settings.whisperModel) (scripts/fetch-models.sh)"
            Log.stt.error("whisper model missing: \(self.model.settings.whisperModel, privacy: .public)")
            return
        }
        loadingModel = true
        sttStatus = "Загружаю модель распознавания…"
        let buffer = self.buffer
        let language = model.settings.language.whisperCode
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { Result { try WhisperEngine(modelPath: path) } }.value
            self?.recognizerLoaded(result, path: path, buffer: buffer, language: language)
        }
    }

    private func recognizerLoaded(_ result: Result<WhisperEngine, Error>, path: String, buffer: AudioRingBuffer, language: String?) {
        loadingModel = false
        switch result {
        case .success(let engine):
            let t = StreamingTranscriber(recognizer: engine, buffer: buffer) { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
            t.setLanguage(language)
            t.setPaused(phase == .paused)
            transcriberBox.set(t)
            transcriber = t
            sttStatus = "Распознавание: \((path as NSString).lastPathComponent)"
        case .failure(let error):
            sttStatus = "Ошибка модели: \(error)"
        }
        onChange?()
    }

    private func handle(_ event: TranscriptEvent) {
        switch event {
        case .speechStarted, .speechEnded:
            break
        case .partial(_, let text):
            partialText = text
            onChange?()
        case .final(let u, let text, let language, _, _):
            partialText = nil
            transcript.append(TranscriptLine(id: u, text: text, language: language))
            if transcript.count > 50 { transcript.removeFirst(transcript.count - 50) }
            onChange?()
        }
        onTranscript?(event)
    }

    /// Ссылка на распознаватель, доступная из очереди захвата.
    private let transcriberBox = TranscriberBox()

    private func makeCapture() -> SystemAudioCapture {
        let buffer = self.buffer
        let meter = levelMeter
        let box = transcriberBox
        return SystemAudioCapture(onSamples: { samples in
            buffer.append(samples)
            meter.add(samples)
            box.get()?.process(samples)
        }, onStop: { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.setPhase(.error(error?.localizedDescription ?? "Захват остановлен"))
            }
        })
    }

    private func startMic() {
        guard Permissions.microphone == .granted else { return }
        if mic == nil {
            mic = MicActivityDetector { [weak self] speaking in
                let t = Double(DispatchTime.now().uptimeNanoseconds) / 1e6
                Task { @MainActor in
                    self?.ownerSpeaking = speaking
                    self?.onOwnerSpeaking?(speaking, t)
                }
            }
        }
        do { try mic?.start() } catch {
            Log.audio.error("mic start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Уровень сигнала раз в 100 мс для индикатора и раз в секунду в лог (только число, без звука).
    private func startLevelReporting() {
        guard levelTask == nil else { return }
        levelTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                self.levelDB = self.levelMeter.takeDB()
                tick += 1
                if tick % 10 == 0, self.phase == .listening {
                    let mic = self.mic?.takePeakDB() ?? -120
                    Log.audio.info("level_db=\(self.levelDB, format: .fixed(precision: 1), privacy: .public) mic_db=\(mic, format: .fixed(precision: 1), privacy: .public) owner_speaking=\(self.ownerSpeaking, privacy: .public)")
                }
            }
        }
    }

    private func setPhase(_ new: Phase) {
        guard phase != new else { return }
        phase = new
        onChange?()
    }
}

final class TranscriberBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: StreamingTranscriber?
    func set(_ t: StreamingTranscriber?) { lock.withLock { value = t } }
    func get() -> StreamingTranscriber? { lock.withLock { value } }
}

/// Пиковый RMS за интервал, потокобезопасно.
final class LevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Float = -120

    func add(_ samples: [Float]) {
        let db = EnergyVAD.rmsDB(samples[...])
        lock.withLock { peak = max(peak, db) }
    }

    func takeDB() -> Float {
        lock.withLock {
            let v = peak
            peak = -120
            return v
        }
    }
}
