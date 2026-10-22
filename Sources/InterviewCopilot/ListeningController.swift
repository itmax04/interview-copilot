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
    /// ИИ-собеседование: распознавание ответа владельца с микрофона (COPILOT-03, R-32). В расшифровку собеседника не попадает.
    var onOwnerTranscript: ((TranscriptEvent) -> Void)?

    struct TranscriptLine: Identifiable, Equatable {
        let id: Int
        let text: String
        let language: String
    }

    private var transcriber: StreamingTranscriber?
    private var loadingModel = false
    private var recognizerGeneration = 0
    private var stopping = false

    /// Буфер последних 30 с звука собеседника (R-04). Читает распознавание (P-04).
    let buffer = AudioRingBuffer(seconds: 30)
    private var capture: SystemAudioCapture?
    /// Микрофон как источник (режим самопроверки, запрос владельца 2026-10-07).
    private var micSource: MicrophoneCapture?
    private var testSource: AudioSourceSetting?
    private var effectiveSource: AudioSourceSetting { testSource ?? model.settings.audioSource }
    private var usesMicrophone: Bool { effectiveSource == .microphone }
    var recognitionReady: Bool { transcriber != nil && phase == .listening }
    private var pausedBeforeTest = false
    private var transcriptBeforeTest: [TranscriptLine] = []
    private let deliveryEpoch = TranscriptDeliveryEpoch()
    /// Какой источник сейчас идёт в распознавание во время ИИ-собеседования; nil — обычная работа.
    private let route = AudioRouteBox()
    private(set) var interviewRoute: AudioRoute?

    /// ИИ-собеседование (COPILOT-03): звук браузера — вопрос интервьюера, как на созвоне;
    /// микрофон — ответ владельца. В распознавание одновременно идёт только один источник.
    func beginInterviewCapture(_ source: AudioSourceSetting) async -> String? {
        if Permissions.microphone == .notDetermined { _ = await Permissions.requestMicrophone() }
        guard Permissions.microphone == .granted else { return "Нет разрешения на микрофон для Interview Copilot" }
        route.set(.call)
        interviewRoute = .call
        await beginTestCallCapture(source)
        let micSource = self.micSource ?? makeMicSource()
        self.micSource = micSource
        do { try micSource.start() } catch { return "Микрофон: \(error)" }
        let t = Double(DispatchTime.now().uptimeNanoseconds) / 1e6
        onOwnerSpeaking?(false, t)
        return nil
    }

    /// Переключение «вопрос → ответ» и обратно. Незаконченные фрагменты прошлого источника отбрасываются.
    func setInterviewRoute(_ value: AudioRoute) {
        guard interviewRoute != nil, interviewRoute != value else { return }
        route.set(value)
        interviewRoute = value
        partialText = nil
        resetTestCallPhrase()
    }

    func endInterviewCapture() async {
        guard interviewRoute != nil else { return }
        micSource?.stop()
        route.set(nil)
        interviewRoute = nil
        await endTestCallCapture()
    }

    func beginTestCallCapture(_ source: AudioSourceSetting) async {
        if testSource == nil {
            pausedBeforeTest = phase == .paused
            transcriptBeforeTest = transcript
            transcript = []
        }
        deliveryEpoch.advance()
        transcriber?.setPaused(true)
        testSource = source
        mic?.stop()
        ownerSpeaking = false
        transcriber?.setPaused(false)
        transcriber?.setLanguage(nil)
        transcriber?.setPromptProvider(nil)
        loadRecognizer()
        startLevelReporting()
        await applySource(restart: true)
    }

    func resetTestCallPhrase() {
        deliveryEpoch.advance()
        transcriber?.setPaused(true)
        transcriber?.setPaused(false)
    }

    func endTestCallCapture() async {
        deliveryEpoch.advance()
        transcriber?.setPaused(true)
        testSource = nil
        transcriber?.setLanguage(model.settings.language.whisperCode)
        transcriber?.setPromptProvider(promptProvider)
        transcript = transcriptBeforeTest
        transcriptBeforeTest = []
        partialText = nil
        if pausedBeforeTest {
            await capture?.stop()
            micSource?.stop()
            source = AudioSourceResolver.resolve(effectiveSource, running: Self.runningApps())
            setPhase(.paused)
        } else {
            if !usesMicrophone { startMic() }
            await applySource(restart: true)
            transcriber?.setPaused(false)
        }
    }
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
        stopping = false
        // Микрофону разрешение «Запись экрана» не нужно.
        guard usesMicrophone || Permissions.screenCaptureGranted else {
            setPhase(.noPermission)
            Log.audio.notice("no screen capture permission")
            return
        }
        loadRecognizer()
        if !usesMicrophone { startMic() }
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
                micSource?.stop()
                mic?.stop()
                buffer.clear()
                setPhase(.paused)
            }
        case .paused:
            if !usesMicrophone { startMic() }
            transcriber?.setPaused(false)
            Task { await applySource(restart: true) }
        default:
            break
        }
    }

    /// Смена источника из меню или настроек — без перезапуска приложения (R-01).
    func sourceSettingChanged() {
        guard phase != .paused else { return }
        if phase == .noPermission && !usesMicrophone { return }
        Task { await applySource(restart: false) }
    }

    private func runningAppsChanged() {
        guard phase != .paused, phase != .noPermission else { return }
        let resolved = AudioSourceResolver.resolve(effectiveSource, running: Self.runningApps())
        if resolved != source { Task { await applySource(restart: false) } }
    }

    private func applySource(restart: Bool, attempt: Int = 0) async {
        let resolved = AudioSourceResolver.resolve(effectiveSource, running: Self.runningApps())
        if resolved == .microphone {
            // Режим самопроверки: системный звук не нужен, микрофон — «собеседник»; определение речи владельца выключено.
            await capture?.stop()
            mic?.stop()
            ownerSpeaking = false
            onOwnerSpeaking?(false, Double(DispatchTime.now().uptimeNanoseconds) / 1e6)
            source = resolved
            let micSource = self.micSource ?? makeMicSource()
            self.micSource = micSource
            do {
                try micSource.start()
                setPhase(.listening)
            } catch {
                setPhase(.error(String(describing: error)))
            }
            return
        }
        // Вернулись к созвону: микрофон снова только для определения речи владельца.
        if micSource?.isRunning == true {
            micSource?.stop()
            startMic()
        }
        guard Permissions.screenCaptureGranted else {
            setPhase(.noPermission)
            return
        }
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
        } catch AudioCaptureError.sourceNotRunning(_) where attempt < 8 {
            // Только что запущенное приложение (Chrome для теста) ScreenCaptureKit видит с задержкой — повторяем.
            try? await Task.sleep(for: .milliseconds(500))
            guard !stopping else { return }
            await applySource(restart: restart, attempt: attempt + 1)
        } catch {
            // Источник не найден: запуск приложения позже снова вызовет захват (runningAppsChanged).
            if case AudioCaptureError.sourceNotRunning = error { source = .none }
            Log.audio.error("capture start failed: \(String(describing: error), privacy: .public)")
            setPhase(.error(String(describing: error)))
        }
    }

    /// Остановка и освобождение модели перед выходом.
    func shutdown() {
        stopping = true
        recognizerGeneration += 1
        transcriberBox.set(nil)
        transcriber?.setPaused(true)
        transcriber = nil
        micSource?.stop()
        mic?.stop()
        let capture = self.capture
        Task { await capture?.stop() }
    }

    /// Подсказка распознаванию из базы (настройка Audio → «Подсказывать словарь базы»).
    func setRecognitionPrompt(_ provider: (@Sendable (String) -> String?)?) {
        promptProvider = provider
        transcriber?.setPromptProvider(testSource == nil ? provider : nil)
    }

    private var promptProvider: (@Sendable (String) -> String?)?

    /// Язык распознавания из настроек (R-03).
    func languageSettingChanged() {
        transcriber?.setLanguage(testSource == nil ? model.settings.language.whisperCode : nil)
    }

    /// Смена модели или режима точности: старая очередь больше не выдаёт текст.
    func recognitionSettingsChanged() {
        recognizerGeneration += 1
        transcriberBox.set(nil)
        transcriber?.setPaused(true)
        transcriber = nil
        partialText = nil
        loadRecognizer()
    }

    /// Загрузка выбранного локального движка в фоне. Без модели слушание идёт, но текста нет.
    private func loadRecognizer() {
        guard !stopping, transcriber == nil, !loadingModel else { return }
        let useParakeet = model.settings.recognitionBackend == .parakeet
            && FileManager.default.fileExists(atPath: AppPaths.parakeetModels.path)
        let path = useParakeet ? AppPaths.parakeetModels.path : AppPaths.model(model.settings.whisperModel).path
        guard FileManager.default.fileExists(atPath: path) else {
            sttStatus = "Нет модели распознавания: \(model.settings.whisperModel) (scripts/fetch-models.sh)"
            Log.stt.error("whisper model missing: \(self.model.settings.whisperModel, privacy: .public)")
            return
        }
        loadingModel = true
        sttStatus = "Загружаю модель распознавания…"
        let buffer = self.buffer
        let reducedContext = !model.settings.recognitionAccuracy
        let generation = recognizerGeneration
        Task { [weak self] in
            let result: Result<any SpeechRecognizer, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    let engine: any SpeechRecognizer
                    if useParakeet { engine = try await ParakeetEngine.load(from: URL(fileURLWithPath: path)) }
                    else { engine = try WhisperEngine(modelPath: path) }
                    return .success(engine)
                } catch { return .failure(error) }
            }.value
            self?.recognizerLoaded(result, path: path, buffer: buffer, reducedContext: reducedContext, generation: generation)
        }
    }

    private func recognizerLoaded(_ result: Result<any SpeechRecognizer, Error>, path: String, buffer: AudioRingBuffer, reducedContext: Bool, generation: Int) {
        loadingModel = false
        guard !stopping else { return }
        guard generation == recognizerGeneration else { loadRecognizer(); return }
        switch result {
        case .success(let engine):
            var config = StreamingTranscriber.Config()
            config.finalReducedContext = reducedContext
            let deliveryEpoch = self.deliveryEpoch
            let t = StreamingTranscriber(recognizer: engine, buffer: buffer, config: config) { [weak self] event in
                let eventEpoch = deliveryEpoch.current()
                Task { @MainActor in
                    guard let self, self.recognizerGeneration == generation, deliveryEpoch.current() == eventEpoch else { return }
                    self.handle(event)
                }
            }
            t.setLanguage(testSource == nil ? model.settings.language.whisperCode : nil)
            t.setPromptProvider(testSource == nil ? promptProvider : nil)
            t.setPaused(phase == .paused)
            transcriberBox.set(t)
            transcriber = t
            let name = engine.nativeMultilingual ? "Parakeet v3" : (path as NSString).lastPathComponent
            let fallback = model.settings.recognitionBackend == .parakeet && !engine.nativeMultilingual
                ? " (Parakeet не установлен, используется Whisper)" : ""
            sttStatus = "Распознавание: \(name)\(fallback)"
        case .failure(let error):
            sttStatus = "Ошибка модели: \(error)"
        }
        onChange?()
    }

    private func handle(_ event: TranscriptEvent) {
        if interviewRoute == .owner {
            onOwnerTranscript?(event)
            return
        }
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
        let route = self.route
        return SystemAudioCapture(onSamples: { samples in
            guard route.accepts(.call) else { return }
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

    private func makeMicSource() -> MicrophoneCapture {
        let buffer = self.buffer
        let meter = levelMeter
        let box = transcriberBox
        let route = self.route
        return MicrophoneCapture { samples in
            guard route.accepts(.owner) else { return }
            buffer.append(samples)
            meter.add(samples)
            box.get()?.process(samples)
        }
    }

    private func startMic() {
        guard testSource == nil, Permissions.microphone == .granted else { return }
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

enum AudioRoute: Equatable, Sendable {
    /// Звук созвона (браузер) — речь собеседника.
    case call
    /// Микрофон — ответ владельца.
    case owner
}

/// Маршрут доступен из очередей захвата.
final class AudioRouteBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: AudioRoute?
    func set(_ v: AudioRoute?) { lock.withLock { value = v } }
    /// Без маршрута (обычная работа) принимается любой запущенный источник.
    func accepts(_ r: AudioRoute) -> Bool { lock.withLock { value == nil || value == r } }
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

/// Не допускает доставки событий старой фразы после сброса или выхода из теста.
final class TranscriptDeliveryEpoch: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func advance() { lock.withLock { value += 1 } }
    func current() -> Int { lock.withLock { value } }
}
