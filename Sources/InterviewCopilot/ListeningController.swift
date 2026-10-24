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
        /// Сессии нет (COPILOT-09 R-02): звук и микрофон не захватываются, модель распознавания загружена заранее.
        case standby
        case error(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var source: ResolvedAudioSource = .none
    /// Уровень сигнала собеседника, dBFS (debug-индикатор P-03).
    private(set) var levelDB: Float = -120
    /// Уровень микрофона владельца для индикатора оверлея (COPILOT-09 R-08).
    private(set) var micLevelDB: Float = -120
    private var micPeakSecond: Float = -120
    /// Каждые 100 мс — для индикаторов оверлея (дёшево: без перерисовки остального).
    var onLevels: (() -> Void)?
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
        /// Причина фильтра («язык de») — строка серым, в подсказки не идёт (COPILOT-05 R-06).
        var filtered: String? = nil
    }

    /// Фильтр отбросил реплику (COPILOT-05 R-06) — текст для ⌃⌥↩ «ответить всё равно».
    var onFiltered: ((String) -> Void)?
    /// Словарь терминов для фильтра языка: встроенный + резюме, вакансия, база (R-05).
    private var terms = TermDictionary()
    /// Silero (R-02): загружается один раз, применяется к распознаванию по настройке.
    private var speechGate: SileroSpeechGate?
    private var speechGateLoading = false

    func setTerms(_ terms: TermDictionary) { self.terms = terms }

    /// Проверка голоса владельца (COPILOT-05 R-03): отпечаток, порог, модель CAM++.
    let voiceGate = VoiceGateBox()
    private var voiceEmbedderLoading = false
    static let voicePrintChanged = Notification.Name("InterviewCopilot.voicePrintChanged")

    /// Перечитать образец и настройки голоса; модель загружается один раз в фоне.
    func voiceSettingsChanged() {
        let settings = model.settings
        voiceGate.update {
            $0.print = VoicePrint.load()
            $0.threshold = Float(settings.ownerVoiceThreshold)
        }
        updateVoiceGateActive()
        guard voiceGate.current.embedder == nil, !voiceEmbedderLoading, VoiceEmbedder.isInstalled(in: AppPaths.models) else { return }
        voiceEmbedderLoading = true
        Task { [weak self] in
            let embedder = await Task.detached(priority: .utility) { try? VoiceEmbedder.load(from: AppPaths.models) }.value
            guard let self else { return }
            self.voiceEmbedderLoading = false
            if embedder == nil { Log.stt.error("CAM++ load failed") }
            self.voiceGate.update { $0.embedder = embedder }
            self.onChange?()
        }
    }

    /// Голос проверяется в режиме «Микрофон Mac» и в ответе владельца на ИИ-собеседовании (R-01, Q13).
    private func updateVoiceGateActive() {
        let micChannel = (testSource == nil && source == .microphone) || interviewRoute == .owner
        voiceGate.update { $0.active = model.settings.ownerVoiceOnly && micChannel }
        enhancerBox.update { $0.active = model.settings.micNoiseSuppression && micChannel }
        updateOwnerChannel()
    }

    /// Настройка «Учитывать мои ответы в подсказках» изменилась.
    func ownerSpeechSettingChanged() { updateOwnerChannel() }

    // MARK: Речь владельца на созвоне (COPILOT-05 R-01, R-07)

    /// Второй распознаватель: микрофон во время созвона. Тот же движок, без уточнения Whisper и без промежуточного текста.
    private var ownerTranscriber: StreamingTranscriber?
    private let ownerBuffer = AudioRingBuffer(seconds: 30)
    private let ownerBox = TranscriberBox()
    private let ownerActive = LockedFlag()
    /// Фраза владельца прошла фильтры — в память интервью (COPILOT-06).
    var onOwnerSaid: ((String) -> Void)?
    /// Уточнённый текст ответа владельца в самопроверке (Whisper приходит через ~3 с, иногда уже после ⌃⌥A): (черновик, итог).
    var onOwnerRevised: ((String, String) -> Void)?
    /// Черновой текст ответов владельца по номеру реплики — до уточнения.
    private var ownerFastText: [Int: String] = [:]

    /// Самопроверка: «сейчас отвечаю я» (⌃⌥A, COPILOT-06) — речь с микрофона идёт ответом в память, а не вопросом.
    private(set) var ownerAnswering = false

    /// Переключить режим ответа. Только в «Микрофон Mac»: на созвоне ответы слышны отдельным каналом сами.
    @discardableResult
    func toggleOwnerAnswering() -> Bool {
        guard testSource == nil, source == .microphone else {
            ownerAnswering = false
            return false
        }
        ownerAnswering.toggle()
        partialText = nil
        Log.app.info("owner answering \(self.ownerAnswering ? "on" : "off", privacy: .public)")
        onChange?()
        return true
    }

    /// Канал владельца работает на созвоне (звук приложения или весь системный звук), не в самопроверке и не в тестах.
    private func updateOwnerChannel() {
        let callSource: Bool = switch source {
        case .app, .allSystem: true
        default: false
        }
        let active = model.settings.ownerSpeechContext && testSource == nil && phase == .listening && callSource
            && Permissions.microphone == .granted
        guard ownerActive.value != active else { return }
        ownerActive.set(active)
        ownerTranscriber?.setPaused(!active)
        Log.audio.info("owner channel \(active ? "on" : "off", privacy: .public)")
    }

    /// Когда в звонке последний раз звучала речь (мс) и звучит ли сейчас — для отсева эха без образца голоса.
    private var callSpeaking = false
    private var callSpeechEndedAt: Double = 0
    static let echoWindowMs: Double = 1500

    private func handleOwner(_ event: TranscriptEvent) {
        guard case .final(_, let text, _, let phraseEnd, _) = event else { return }
        // Без образца голоса эхо интервьюера из динамиков неотличимо по языку: фраза микрофона, закончившаяся,
        // пока в звонке шла речь или в пределах 1,5 с после неё, считается эхом (как правило эха TurnDetector, S-07).
        if voiceGate.current.print == nil {
            let end = Double(phraseEnd) / 1e6
            if callSpeaking || end - callSpeechEndedAt < Self.echoWindowMs {
                Log.metrics.notice("filtered reason=echo channel=mic")
                return
            }
        }
        // Без образца голоса — хотя бы фильтр языка микрофона: ТВ на другом языке не станет «ответом владельца».
        if voiceGate.current.print == nil, model.settings.languageFilter,
           case .drop = LanguageGate(setting: model.settings.language, terms: terms).check(text, channel: .mic) { return }
        onOwnerSaid?(text)
        Log.metrics.notice("owner_final words=\(TurnDetectorWords.count(text))")
    }

    /// Шумоподавление микрофона LocalVQE (R-04, по умолчанию выключено): модель загружается при включении.
    let enhancerBox = EnhancerBox()
    private var enhancerLoading = false

    func noiseSuppressionSettingChanged() {
        updateVoiceGateActive()
        guard model.settings.micNoiseSuppression, enhancerBox.current.enhancer == nil, !enhancerLoading,
              SpeechEnhancer.isInstalled(in: AppPaths.models) else { return }
        enhancerLoading = true
        Task { [weak self] in
            let enhancer = await Task.detached(priority: .utility) { try? SpeechEnhancer.load(from: AppPaths.models) }.value
            guard let self else { return }
            self.enhancerLoading = false
            if enhancer == nil { Log.stt.error("LocalVQE load failed") }
            self.enhancerBox.update { $0.enhancer = enhancer }
        }
    }

    var voiceStatus: String {
        let s = voiceGate.current
        if !VoiceEmbedder.isInstalled(in: AppPaths.models) { return "Модель CAM++ не установлена: scripts/fetch-filter-models.py" }
        guard let print = s.print else { return "Образец голоса не записан" }
        let threshold = voiceGate.effectiveThreshold ?? print.recommendedThreshold
        return String(format: "Образец: %.0f с речи · порог %.2f%@", print.speechSeconds, threshold, s.embedder == nil ? " · загружаю модель…" : "")
    }

    /// Канал для фильтра языка: звонок, весь системный звук или микрофон (R-01, Q8).
    private var gateChannel: LanguageGate.Channel {
        switch source {
        case .allSystem: .allSystem
        case .microphone: .mic
        case .app, .none: .call
        }
    }

    /// Причина отбросить реплику или nil. Тестовый звонок не фильтруется: он меряет само распознавание.
    private func filterReason(_ text: String) -> String? {
        guard testSource == nil, model.settings.languageFilter else { return nil }
        let gate = LanguageGate(setting: model.settings.language, terms: terms)
        guard case .drop(let language) = gate.check(text, channel: gateChannel) else { return nil }
        Log.metrics.notice("filtered reason=lang channel=\(self.gateChannel.rawValue, privacy: .public) lang=\(language, privacy: .public)")
        return "язык \(language)"
    }

    /// Загрузка Silero в фоне (если включено и модель установлена) и подключение к распознаванию.
    func speechGateSettingChanged() {
        guard model.settings.neuralSpeechGate else { applySpeechGate(); return }
        guard speechGate == nil, !speechGateLoading, SileroSpeechGate.isInstalled(in: AppPaths.models) else { applySpeechGate(); return }
        speechGateLoading = true
        Task { [weak self] in
            let gate = await Task.detached(priority: .utility) { try? SileroSpeechGate.load(from: AppPaths.models) }.value
            guard let self else { return }
            self.speechGateLoading = false
            self.speechGate = gate
            if gate == nil { Log.stt.error("silero vad load failed") }
            self.applySpeechGate()
        }
    }

    var speechGateStatus: String {
        if !SileroSpeechGate.isInstalled(in: AppPaths.models) { return "Модель Silero не установлена: scripts/fetch-filter-models.py" }
        return speechGate == nil ? "Загружаю Silero…" : "Silero загружена"
    }

    /// Порог громкости по источнику: у микрофона шум комнаты громче, чем тишина в звуке звонка (COPILOT-05).
    private func applyVADConfig() {
        transcriber?.setVADConfig(source == .microphone ? StreamingTranscriber.microphoneVAD : StreamingTranscriber.Config().vad)
        updateVoiceGateActive()
    }

    private func applySpeechGate() {
        let gate = model.settings.neuralSpeechGate && testSource == nil ? speechGate : nil
        transcriber?.setSpeechGate(gate.map { g in { @Sendable samples in g.isSpeech(samples) } })
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
    private var standbyBeforeTest = false
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
        updateVoiceGateActive()
        partialText = nil
        resetTestCallPhrase()
    }

    func endInterviewCapture() async {
        guard interviewRoute != nil else { return }
        micSource?.stop()
        route.set(nil)
        interviewRoute = nil
        updateVoiceGateActive()
        await endTestCallCapture()
    }

    func beginTestCallCapture(_ source: AudioSourceSetting) async {
        if testSource == nil {
            pausedBeforeTest = phase == .paused
            standbyBeforeTest = phase == .standby
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
        if standbyBeforeTest {
            // Тест или ИИ-собеседование без сессии — после них снова не слушаем (COPILOT-09 R-02).
            await capture?.stop()
            micSource?.stop()
            setPhase(.standby)
        } else if pausedBeforeTest {
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
        case .standby: .noSession
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

    /// Без сессии: всё остановлено, распознавание загружено заранее — старт сессии не ждёт модель (COPILOT-09 R-02).
    func enterStandby() {
        stopping = false
        transcriber?.setPaused(true)
        partialText = nil
        ownerAnswering = false
        setPhase(.standby)
        loadRecognizer()
        Task {
            await capture?.stop()
            micSource?.stop()
            mic?.stop()
            buffer.clear()
        }
    }

    /// Clear в оверлее (COPILOT-09 Q13): расшифровка на экране и «последние реплики» для следующего ответа.
    func clearTranscript() {
        transcript = []
        partialText = nil
        onChange?()
    }

    /// Загрузить модель распознавания заранее, ничего не захватывая.
    func warmUp() { loadRecognizer() }

    /// Начало сессии: расшифровка с чистого листа, захват по источнику из настроек.
    func startSession() {
        transcript = []
        partialText = nil
        start()
    }

    /// Запуск при старте приложения и после выдачи разрешений.
    func start() {
        stopping = false
        transcriber?.setPaused(false)
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
        guard phase != .paused, phase != .standby else { return }
        if phase == .noPermission && !usesMicrophone { return }
        Task { await applySource(restart: false) }
    }

    private func runningAppsChanged() {
        guard phase != .paused, phase != .noPermission, phase != .standby else { return }
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
            applyVADConfig()
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
        if resolved != .microphone { ownerAnswering = false }
        applyVADConfig()
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

    // MARK: Проверка перед стартом (COPILOT-09 R-03)

    /// Пиковый уровень микрофона за `seconds`; nil — нет разрешения или микрофон не запустился.
    func probeMicrophone(seconds: Double = 2) async -> Float? {
        guard Permissions.microphone == .granted else { return nil }
        let meter = LevelMeter()
        let probe = MicrophoneCapture { samples in meter.add(samples) }
        do { try probe.start() } catch { return nil }
        try? await Task.sleep(for: .seconds(seconds))
        probe.stop()
        return meter.takeDB()
    }

    /// Источник звонка по настройке и пиковый уровень его звука за `seconds` (только уровень — без распознавания).
    func probeCall(seconds: Double = 3) async -> (name: String?, peak: Float?) {
        let resolved = AudioSourceResolver.resolve(model.settings.audioSource, running: Self.runningApps())
        guard resolved != .none, resolved != .microphone, Permissions.screenCaptureGranted else { return (resolved.displayName, nil) }
        let meter = LevelMeter()
        let probe = SystemAudioCapture(onSamples: { samples in meter.add(samples) }, onStop: { _ in })
        do { try await probe.start(resolved) } catch { return (resolved.displayName, nil) }
        try? await Task.sleep(for: .seconds(seconds))
        await probe.stop()
        return (resolved.displayName, meter.takeDB())
    }

    var recognizerLoaded: Bool { transcriber != nil }

    /// Остановка и освобождение модели перед выходом.
    func shutdown() {
        stopping = true
        recognizerGeneration += 1
        transcriberBox.set(nil)
        transcriber?.setPaused(true)
        transcriber = nil
        ownerBox.set(nil)
        ownerTranscriber?.setPaused(true)
        ownerTranscriber = nil
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
        ownerTranscriber?.setLanguage(model.settings.language.whisperCode)
    }

    /// Смена модели или режима точности: старая очередь больше не выдаёт текст.
    func recognitionSettingsChanged() {
        recognizerGeneration += 1
        transcriberBox.set(nil)
        transcriber?.setPaused(true)
        transcriber = nil
        ownerBox.set(nil)
        ownerTranscriber?.setPaused(true)
        ownerTranscriber = nil
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
        // Гибрид для украинского (R-35): итог украинской фразы — Whisper turbo с языком uk, если файл модели есть.
        let turbo = AppPaths.model("ggml-large-v3-turbo-q5_0.bin").path
        let hybrid = useParakeet && (model.settings.ukrainianWhisperFinal || model.settings.whisperReviseAllLanguages)
            && FileManager.default.fileExists(atPath: turbo)
        let reviseAll = model.settings.whisperReviseAllLanguages
        let generation = recognizerGeneration
        Task { [weak self] in
            let result: Result<any SpeechRecognizer, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    let engine: any SpeechRecognizer
                    if useParakeet {
                        let parakeet = try await ParakeetEngine.load(from: URL(fileURLWithPath: path))
                        engine = hybrid ? HybridRecognizer(primary: parakeet, reviseAllLanguages: reviseAll,
                                                           loadVerifier: { try WhisperEngine(modelPath: turbo) }) : parakeet
                    } else { engine = try WhisperEngine(modelPath: path) }
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
            if source == .microphone { config.vad = StreamingTranscriber.microphoneVAD }
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
            let gate = model.settings.neuralSpeechGate && testSource == nil ? speechGate : nil
            t.setSpeechGate(gate.map { g in { @Sendable samples in g.isSpeech(samples) } })
            let voiceGate = self.voiceGate
            t.setVoiceGate { samples in voiceGate.check(samples) }
            let enhancerBox = self.enhancerBox
            t.setAudioEnhancer { samples in enhancerBox.enhance(samples) }
            t.setPaused(phase == .paused || phase == .standby)
            transcriberBox.set(t)
            transcriber = t
            var ownerConfig = StreamingTranscriber.Config()
            ownerConfig.partialInterval = 3600        // промежуточный текст владельца не нужен
            ownerConfig.allowRevision = false
            ownerConfig.vad = StreamingTranscriber.microphoneVAD
            let ot = StreamingTranscriber(recognizer: engine, buffer: ownerBuffer, config: ownerConfig) { [weak self] event in
                Task { @MainActor in
                    guard let self, self.recognizerGeneration == generation else { return }
                    self.handleOwner(event)
                }
            }
            ot.setLanguage(model.settings.language.whisperCode)
            ot.setSpeechGate(gate.map { g in { @Sendable samples in g.isSpeech(samples) } })
            // Эхо интервьюера из динамиков и чужие голоса отсекает отпечаток голоса (решение исполнителя, этап 4).
            ot.setVoiceGate { samples in voiceGate.check(samples, ignoringActive: true) }
            ot.setPaused(!ownerActive.value)
            ownerBox.set(ot)
            ownerTranscriber = ot
            updateOwnerChannel()
            let name = engine is HybridRecognizer ? (model.settings.whisperReviseAllLanguages ? "Parakeet v3 + уточнение Whisper turbo" : "Parakeet v3 + Whisper turbo (UK)")
                : engine.nativeMultilingual ? "Parakeet v3" : (path as NSString).lastPathComponent
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
        // Уточнение ответа владельца — и после выхода из режима ответа: реплика уже записана ответом, не вопросом.
        if case .revised(let u, let text, _) = event, let fast = ownerFastText.removeValue(forKey: u) {
            onOwnerRevised?(fast, text)
            return
        }
        // Самопроверка, режим ответа (⌃⌥A): итог — ответ владельца в память; для хода — как шум, вопросов нет.
        if ownerAnswering, source == .microphone {
            switch event {
            case .final(let u, let text, _, let phraseEnd, _):
                ownerFastText[u] = text
                if ownerFastText.count > 20, let oldest = ownerFastText.keys.min() { ownerFastText.removeValue(forKey: oldest) }
                onOwnerSaid?(text)
                Log.metrics.notice("owner_final words=\(TurnDetectorWords.count(text)) mode=self-test")
                onTranscript?(.discarded(utterance: 0, phraseEnd: phraseEnd))
            case .foreignVoice(_, _, _, let phraseEnd):
                onTranscript?(.discarded(utterance: 0, phraseEnd: phraseEnd))
            default:
                break   // промежуточный текст ответа не показываем как реплику интервьюера
            }
            return
        }
        switch event {
        case .speechStarted:
            callSpeaking = true
        case .speechEnded(_, let at):
            callSpeaking = false
            callSpeechEndedAt = Double(at) / 1e6
        case .partial(_, let text):
            partialText = text
            onChange?()
        case .final(let u, let text, let language, let phraseEnd, _):
            partialText = nil
            if let reason = filterReason(text) {
                // R-06: серой строкой; для хода и истории — как отброшенный шум.
                transcript.append(TranscriptLine(id: u, text: text, language: language, filtered: reason))
                if transcript.count > 50 { transcript.removeFirst(transcript.count - 50) }
                onChange?()
                onFiltered?(text)
                onTranscript?(.discarded(utterance: u, phraseEnd: phraseEnd))
                return
            }
            transcript.append(TranscriptLine(id: u, text: text, language: language))
            if transcript.count > 50 { transcript.removeFirst(transcript.count - 50) }
            onChange?()
        case .revising, .discarded:
            break
        case .foreignVoice(let u, let text, let similarity, let phraseEnd):
            // R-03, R-06: чужой голос — серой строкой; для хода — как шум.
            partialText = nil
            transcript.append(TranscriptLine(id: u, text: text, language: "", filtered: String(format: "чужой голос %.2f", similarity)))
            if transcript.count > 50 { transcript.removeFirst(transcript.count - 50) }
            onChange?()
            onFiltered?(text)
            onTranscript?(.discarded(utterance: u, phraseEnd: phraseEnd))
            return
        case .revised(let u, let text, let language):
            // Уточнённый итог (R-37) подменяет строку реплики в расшифровке.
            if let i = transcript.lastIndex(where: { $0.id == u }) {
                transcript[i] = TranscriptLine(id: u, text: text, language: language, filtered: transcript[i].filtered)
                onChange?()
                // Отфильтрованная реплика остаётся отфильтрованной: ход по ней уже не ждут.
                if transcript[i].filtered != nil { return }
            }
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
            Task { @MainActor in self?.captureStopped(error) }
        })
    }

    /// Время перезапусков захвата за последние 10 минут (R-39).
    private var captureRestarts: [Date] = []

    /// Захват остановили macOS или значок записи в строке меню (R-39). На собеседовании нельзя молча перестать слышать:
    /// перезапускаем через 1 с, не больше 5 раз за 10 минут; дальше — понятная ошибка в панели.
    private func captureStopped(_ error: Error?) {
        guard !stopping, phase != .paused, phase != .noPermission, phase != .standby else { return }
        let reason = error?.localizedDescription ?? "?"
        let now = Date()
        captureRestarts = captureRestarts.filter { now.timeIntervalSince($0) < 600 }
        guard captureRestarts.count < 5 else {
            Log.audio.error("capture stopped, restarts exhausted: \(reason, privacy: .public)")
            setPhase(.error("Захват звука остановлен macOS (\(reason)). Пауза → Продолжить, чтобы включить снова."))
            return
        }
        captureRestarts.append(now)
        Log.audio.notice("capture_restart attempt=\(self.captureRestarts.count) reason=\(reason, privacy: .public)")
        setPhase(.error("Захват звука остановлен — перезапускаю…"))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !self.stopping, self.phase != .paused, self.phase != .standby else { return }
            await self.applySource(restart: true)
        }
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
            // R-07: тот же микрофон — в распознавание речи владельца, пока канал включён.
            let buffer = ownerBuffer, box = ownerBox, active = ownerActive
            mic?.onSamples = { samples in
                guard active.value else { return }
                buffer.append(samples)
                box.get()?.process(samples)
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
                self.micLevelDB = self.mic?.takePeakDB() ?? (self.source == .microphone ? self.levelDB : -120)
                self.micPeakSecond = max(self.micPeakSecond, self.micLevelDB)
                self.onLevels?()
                tick += 1
                if tick % 10 == 0, self.phase == .listening {
                    let mic = self.micPeakSecond
                    self.micPeakSecond = -120
                    Log.audio.info("level_db=\(self.levelDB, format: .fixed(precision: 1), privacy: .public) mic_db=\(mic, format: .fixed(precision: 1), privacy: .public) owner_speaking=\(self.ownerSpeaking, privacy: .public)")
                }
            }
        }
    }

    private func setPhase(_ new: Phase) {
        guard phase != new else { return }
        phase = new
        updateOwnerChannel()
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

/// Флаг, доступный из очередей захвата.
final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    func set(_ v: Bool) { lock.withLock { flag = v } }
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
