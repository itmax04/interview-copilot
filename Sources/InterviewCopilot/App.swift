import AppKit
import CopilotCore

@main
@MainActor
enum InterviewCopilotMain {
    static func main() {
        // Служебный режим для scripts/build-app.sh: отрисовать иконку приложения в .iconset.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--export-iconset"), i + 1 < args.count {
            do {
                try ParrotIcon.exportIconset(to: URL(fileURLWithPath: args[i + 1]))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("export-iconset: \(error)\n".utf8))
                exit(1)
            }
        }

        if let i = args.firstIndex(of: "--smoke-screenshot"), i + 1 < args.count {
            setvbuf(stdout, nil, _IOLBF, 0)
            exit(SmokeTest.screenshot(path: args[i + 1]))
        }
        if let i = args.firstIndex(of: "--ui-snapshots"), i + 1 < args.count {
            setvbuf(stdout, nil, _IOLBF, 0)
            NSApplication.shared.setActivationPolicy(.accessory)
            exit(UISnapshots.run(to: URL(fileURLWithPath: args[i + 1])))
        }
        if let i = args.firstIndex(of: "--smoke-memory") {
            setvbuf(stdout, nil, _IOLBF, 0)
            exit(SmokeTest.memory(runs: (i + 1 < args.count ? Int(args[i + 1]) : nil) ?? 3))
        }
        if let i = args.firstIndex(of: "--smoke-task"), i + 1 < args.count {
            setvbuf(stdout, nil, _IOLBF, 0)
            exit(SmokeTest.task(path: args[i + 1]))
        }
        if args.contains("--smoke-review") {
            setvbuf(stdout, nil, _IOLBF, 0)
            exit(SmokeTest.review())
        }
        if args.contains("--smoke-session") {
            setvbuf(stdout, nil, _IOLBF, 0)
            exit(SmokeTest.session())
        }
        if args.contains("--smoke-prepare") {
            setvbuf(stdout, nil, _IOLBF, 0)
            exit(SmokeTest.prepare())
        }
        if args.contains("--smoke-llm") {
            setvbuf(stdout, nil, _IOLBF, 0)
            exit(SmokeTest.run())
        }

        let app = NSApplication.shared
        let delegate = AppDelegate(testCallOnly: args.contains("--test-call"), openInterviewer: args.contains("--ai-interview"),
                                   openSettings: args.contains("--settings"), openProfile: args.contains("--profile"))
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let testCallOnly: Bool
    private let openInterviewer: Bool
    /// `--settings`: открыть настройки (вкладка Keys) сразу при запуске — ввод ключей без мыши и меню.
    private let openSettings: Bool
    /// `--profile`: открыть окно «Профиль» при запуске (COPILOT-08) — загрузка резюме без мыши и меню.
    private let openProfile: Bool
    init(testCallOnly: Bool = false, openInterviewer: Bool = false, openSettings: Bool = false, openProfile: Bool = false) {
        self.testCallOnly = testCallOnly
        self.openInterviewer = openInterviewer && !testCallOnly
        self.openSettings = openSettings
        self.openProfile = openProfile
        super.init()
    }
    private let model = AppModel()
    private lazy var testCall = TestCallController(listening: listening)
    // «Без профиля» (R-40): интервьюер не видит резюме и вакансию и задаёт общие вопросы.
    private lazy var interviewer = InterviewerController(listening: listening, model: model, profile: { [bank, model] in
        model.settings.useProfile ? bank.profile : Profile(name: MenuLayout.noProfileTitle)
    })
    private lazy var listening = ListeningController(model: model)
    private var menuBar: MenuBarController?
    private lazy var settingsWindow = SettingsWindowController(model: model, hotkeyFailures: { [weak self] in
        self?.hotkeys?.failures ?? [:]
    }, stylePreviewContext: { [weak self] in
        guard let self else { return nil }
        // Ответ по умолчанию (R-12) — предпросмотр по активному профилю, как собеседование.
        return StylePreview.Context(settings: self.model.settings, secrets: self.model.secrets,
                                    profile: self.model.settings.useProfile ? self.bank.profile : nil,
                                    generalInstructions: self.bank.generalInstructions,
                                    language: self.model.settings.language.whisperCode ?? "uk")
    })
    /// Главное окно (COPILOT-09 этап 6, P12): «Сегодня», «Сессии», «Профили», «ИИ-собеседование», «Настройки».
    private let workspaceModel = WorkspaceModel()
    private lazy var workspace = WorkspaceWindowController(
        workspace: workspaceModel, model: model, bank: bank, store: sessions.store, reviews: reviews,
        hotkeyFailures: { [weak self] in self?.hotkeys?.failures ?? [:] },
        stylePreviewContext: { [weak self] in
            guard let self else { return nil }
            return StylePreview.Context(settings: self.model.settings, secrets: self.model.secrets,
                                        profile: self.model.settings.useProfile ? self.bank.profile : nil,
                                        generalInstructions: self.bank.generalInstructions,
                                        language: self.model.settings.language.whisperCode ?? "uk")
        })
    private lazy var permissionsWindow = PermissionsWindowController(listening: listening)
    private lazy var onboarding: OnboardingWindowController = makeOnboarding()

    private func makeOnboarding() -> OnboardingWindowController {
        OnboardingWindowController(model: model, listening: listening) { [weak self] in
            self?.onboarding.close()
            self?.listening.enterStandby()
        }
    }
    private let panelModel = PanelModel()
    private lazy var panel = PanelController(model: panelModel)
    private lazy var turns = TurnController(thresholdMs: model.settings.pauseThresholdMs)
    private let bank = BankController()
    private lazy var answers = AnswerController(model: model, bank: bank, panel: panelModel)
    private let sessions = SessionController()
    private lazy var reviews = ReviewController(store: sessions.store, model: model, bank: bank)
    private lazy var historyWindow = SessionHistoryWindowController(sessions: sessions, reviews: reviews)
    private lazy var profileWindow = ProfileWindowController(bank: bank, model: model)
    /// Живая сессия и мастер «Создать сессию» (COPILOT-09).
    private let liveSession = LiveSessionController()
    private lazy var wizard = SessionWizardController(model: model, bank: bank, listening: listening) { [weak self] config in
        self?.startSession(config)
    }
    private lazy var usage: UsageMeter = {
        let url = Bundle.main.url(forResource: "pricing", withExtension: "json")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/pricing.json")
        let pricing = (try? Pricing.load(url)) ?? Pricing.empty
        return UsageMeter(pricing: pricing, storage: AppPaths.root.appendingPathComponent("usage.json"))
    }()
    private var hotkeys: HotkeyCenter?
    private var lastSettings: AppSettings?

    func applicationWillTerminate(_ notification: Notification) {
        // Модели освобождаются до выхода: иначе ggml-metal падает в статических деструкторах.
        testCall.stopServer()
        interviewer.stopServer()
        sessions.finish()
        bank.shutdown()
        listening.shutdown()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        let menuBar = MenuBarController(onAction: { [weak self] action in self?.handle(action) })
        menuBar.sourceMenuData = { [weak self] in
            (self?.model.settings.audioSource ?? .auto, ListeningController.runningApps())
        }
        menuBar.onSelectSource = { [weak self] value in self?.model.settings.audioSource = value }
        menuBar.onSelectMode = { [weak self] mode in self?.model.settings.mode = mode }
        menuBar.onSelectLanguage = { [weak self] lang in self?.model.settings.language = lang }
        menuBar.onSelectUseProfile = { [weak self] use in self?.model.settings.useProfile = use }
        menuBar.onSelectProfile = { [weak self] id in
            self?.bank.select(id)
            self?.model.settings.useProfile = true
        }
        menuBar.onSelectStrongModel = { [weak self] p in self?.model.settings.strongProvider = p }
        menuBar.providersWithKeys = { [weak self] in
            Set(ProviderID.allCases.filter { self?.model.hasKey[$0] == true })
        }
        menuBar.strongProvider = { [weak self] in self?.model.settings.strongProvider ?? .anthropic }
        self.menuBar = menuBar

        hotkeys = HotkeyCenter { [weak self] action in self?.handle(action) }
        lastSettings = model.settings
        applyAppearance()
        applySettings(force: true)

        model.onChange = { [weak self] in self?.settingsChanged() }
        listening.onChange = { [weak self] in self?.refreshUI() }
        listening.onLevels = { [weak self] in
            guard let self, self.liveSession.isActive, self.panel.isVisible else { return }
            self.updateLevels()
        }
        listening.onTranscript = { [weak self] event in
            guard let self else { return }
            if self.testCall.active { self.testCall.handleTranscript(event); return }
            guard !self.testCallOnly else { return }
            // ИИ-собеседование: вопрос сверяется с текстом модели и при этом идёт в обычные подсказки, как на созвоне.
            if self.interviewer.active { self.interviewer.handleCallTranscript(event) }
            self.turns.handle(event)
            // Собеседник снова говорит — прежний статус распознавания устарел.
            if case .speechStarted = event, self.panelModel.detection != .idle {
                self.panelModel.detection = self.panelModel.detection.next(on: .speechStarted)
            }
            if case .final(let u, let text, let lang, _, _) = event {
                self.sessions.addUtterance(id: u, text: text, language: lang)
                self.fastText[u] = text
                if self.fastText.count > 50, let oldest = self.fastText.keys.min() { self.fastText.removeValue(forKey: oldest) }
            }
            if case .revised(let u, let text, let lang) = event {
                self.sessions.reviseUtterance(id: u, text: text, language: lang)
                // COPILOT-06: уточнённый текст — и в память интервью (живой тест: туда попадал черновой Parakeet).
                if let fast = self.fastText.removeValue(forKey: u) { self.memory.reviseText(fast, to: text); self.saveMemory() }
            }
        }
        listening.onOwnerSpeaking = { [weak self] speaking, t in
            guard let self, !self.testCall.active else { return }
            self.turns.ownerSpeaking(speaking, at: t)
        }
        testCall.onBegin = { [weak self] in
            self?.answers.cancel()
            self?.turns.stop()
        }
        testCall.onEnd = { [weak self] in
            guard let self else { return }
            if self.testCallOnly {
                // Служебный локальный запуск не включает облачные ответы после закрытия теста.
                self.listening.togglePause()
            } else if self.liveSession.isActive, self.listening.phase != .paused { self.turns.start() }
            self.refreshUI()
        }
        testCall.onPermissions = { [weak self] in self?.permissionsWindow.show() }
        listening.onOwnerTranscript = { [weak self] event in self?.interviewer.handleOwnerTranscript(event) }
        interviewer.onEnd = { [weak self] in
            // ИИ-собеседование — сессия типа Mock (COPILOT-09 R-06): закончилось оно — закончилась и сессия.
            guard let self else { return }
            if self.liveSession.isActive, self.liveSession.config.type == .mock { self.liveSession.end() }
            self.refreshUI()
        }
        interviewer.onOwnerAnswer = { [weak self] text in
            self?.memory.addAnswer(text)
            self?.saveMemory()
        }
        interviewer.onPermissions = { [weak self] in self?.permissionsWindow.show() }
        interviewer.onUsage = { [weak self] provider, modelID, u in self?.recordUsage(provider, modelID, u) }
        interviewer.onProviderError = { [weak self] provider, error in
            self?.usage.recordError(provider: provider, error: error)
            self?.refreshUI()
        }
        turns.onTurn = { [weak self] turn in self?.turnCompleted(turn) }
        turns.onDraft = { [weak self] text in self?.draftReady(text) }
        listening.onFiltered = { [weak self] text in self?.turns.filtered(text) }
        // Образец голоса записан или удалён в настройках (COPILOT-05 R-03).
        NotificationCenter.default.addObserver(forName: ListeningController.voicePrintChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.listening.voiceSettingsChanged() }
        }
        panelModel.onAnswerFiltered = { [weak self] text in self?.turns.answerFiltered(text) }

        panelModel.onOpenSettings = { [weak self] in self?.workspace.show(.settings) }
        panelModel.onOpenPermissions = { [weak self] in self?.permissionsWindow.show() }
        panelModel.onRetry = { [weak self] in
            guard let self else { return }
            if self.liveSession.isActive { self.listening.start() } else { self.listening.enterStandby() }
        }
        panelModel.onCreateSession = { [weak self] in self?.showWizard() }
        panelModel.onEndSession = { [weak self] in self?.liveSession.end() }
        panelModel.onStartDetectedCall = { [weak self] in
            guard let self else { return }
            self.startSession(self.wizard.defaultConfig())
        }
        panelModel.onDismissDetectedCall = { [weak self] in self?.liveSession.dismissDetectedCall() }
        setupOverlayActions()
        answers.onTaskChange = { [weak self] task in
            self?.panelModel.taskImages = task?.images ?? []
            self?.panelModel.taskSolved = task.map { !$0.solution.isEmpty } ?? false
            self?.panelModel.taskTitle = task?.statement
        }
        panelModel.onCloseTask = { [weak self] in self?.answers.clearTask() }
        liveSession.onStart = { [weak self] config in self?.sessionStarted(config) }
        liveSession.onEnd = { [weak self] config in self?.sessionEnded(config) }
        liveSession.onTick = { [weak self] in self?.refreshUI() }
        liveSession.runningApps = { ListeningController.runningApps().map(\.bundleID) }
        liveSession.detectionAllowed = { [weak self] in
            guard let self else { return false }
            return !self.testCall.active && !self.interviewer.active && self.model.settings.onboardingCompleted
        }
        answers.session = { [weak self] in
            guard let self, self.liveSession.isActive else { return nil }
            return self.liveSession.effectiveConfig
        }

        bank.onChange = { [weak self] in
            self?.updateRecognitionPrompt()
            self?.updateFilterTerms()
            self?.refreshUI()
        }
        // В промпт — только реплики интервьюера, прошедшие фильтры (серые строки COPILOT-05 не идут).
        answers.transcript = { [weak self] in self?.listening.transcript.filter { $0.filtered == nil }.map(\.text) ?? [] }
        answers.onUsage = { [weak self] provider, modelID, u in self?.recordUsage(provider, modelID, u) }
        answers.onProviderError = { [weak self] provider, error in
            self?.usage.recordError(provider: provider, error: error)
            self?.refreshUI()
        }
        answers.onAnswer = { [weak self] record in
            guard let self else { return }
            self.sessions.addAnswer(record)
            // COPILOT-06: подсказка — в обмен этого хода (замена ответа, если он не записан, и разбор после звонка).
            if !record.text.isEmpty, record.turn.id >= 0 { self.memory.setHint(record.text, forTurn: record.turn.id); self.saveMemory() }
        }
        answers.onNotAQuestion = { [weak self] turn in
            guard let self else { return }
            self.panelModel.detection = self.panelModel.detection.next(on: .notAQuestion)
            guard self.memory.dropUnanswered(turnID: turn.id) else { return }
            self.saveMemory()
        }
        // COPILOT-06: ответы владельца — в обменах памяти интервью.
        answers.memory = memory
        answers.embed = { [weak self] in self?.bank.embedFunction }
        listening.onOwnerSaid = { [weak self] text in
            self?.memory.addAnswer(text)
            self?.sessions.addOwnerUtterance(text)
            self?.saveMemory()
        }
        listening.onOwnerRevised = { [weak self] fast, text in
            self?.memory.reviseText(fast, to: text)
            self?.sessions.reviseOwnerUtterance(fast, to: text)
            self?.saveMemory()
        }
        if testCallOnly {
            testCall.start()
            refreshUI()
            return
        }
        sessions.currentSource = { [weak self] in self?.listening.source.displayName }
        bank.onActiveProfileChange = { [weak self] id in self?.model.settings.activeProfileID = id }
        bank.start(embeddingModel: model.settings.embeddingModel, activeProfileID: model.settings.activeProfileID)

        // COPILOT-09 R-02: без сессии приложение не слушает; модель распознавания загружается заранее.
        listening.enterStandby()
        liveSession.startTicking()
        model.verifyModelIDs()
        refreshUI()
        panel.show()
        onboarding.state.refresh()
        if !model.settings.onboardingCompleted || !onboarding.state.allModelsPresent {
            // S-09: мастер первого запуска (разрешения → ключ → модели).
            onboarding.show()
        } else if listening.phase == .noPermission {
            // AC-13: без разрешения — понятное состояние и инструкция, без падения.
            permissionsWindow.show()
        }
        startDownloadProgressMirror()
        setupWorkspace()
        if openInterviewer { handle(MenuAction.aiInterview) }
        if openSettings { workspace.show(.settings) }
        if openProfile { workspace.show(.profiles) }
        // P12: главное окно — домашний экран; при первом запуске сначала мастер.
        if model.settings.onboardingCompleted, !openSettings, !openProfile, !openInterviewer { workspace.show(.today) }
    }

    private func recordUsage(_ provider: ProviderID, _ modelID: String, _ u: TokenUsage) {
        let s = model.settings
        if usage.record(provider: provider, model: modelID, usage: u, settings: s), !s.paidProvidersSuspended {
            // Лимит месяца: платные провайдеры выключаются до подтверждения владельцем (R-18 Budget).
            model.settings.paidProvidersSuspended = true
            Log.app.notice("monthly budget reached, paid providers suspended")
        }
        refreshUI()
    }

    private func settingsChanged() {
        applyAppearance()
        applySettings(force: false)
        refreshUI()
    }

    /// Тема окон (COPILOT-10): «как в системе» — appearance не задается; оверлей закреплен темным в PanelController.
    private func applyAppearance() {
        let wanted: NSAppearance? = switch model.settings.theme {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        if NSApp.appearance?.name != wanted?.name { NSApp.appearance = wanted }
    }

    private func applySettings(force: Bool) {
        let s = model.settings
        let old = lastSettings ?? s
        if force || s.hotkeys != old.hotkeys {
            hotkeys?.register(Dictionary(uniqueKeysWithValues: HotkeyAction.allCases.map { ($0, s.hotkey($0)) }))
        }
        if !force && s.audioSource != old.audioSource { listening.sourceSettingChanged() }
        if !force && (s.recognitionBackend != old.recognitionBackend || s.whisperModel != old.whisperModel || s.recognitionAccuracy != old.recognitionAccuracy || s.ukrainianWhisperFinal != old.ukrainianWhisperFinal
            || s.whisperReviseAllLanguages != old.whisperReviseAllLanguages) {
            testCall.recognitionChanged()
            interviewer.recognitionChanged()
            listening.recognitionSettingsChanged()
        }
        if !force && s.language != old.language { listening.languageSettingChanged() }
        if force || s.neuralSpeechGate != old.neuralSpeechGate { listening.speechGateSettingChanged() }
        if force || s.ownerVoiceOnly != old.ownerVoiceOnly || s.ownerVoiceThreshold != old.ownerVoiceThreshold { listening.voiceSettingsChanged() }
        if force || s.micNoiseSuppression != old.micNoiseSuppression { listening.noiseSuppressionSettingChanged() }
        if !force && s.ownerSpeechContext != old.ownerSpeechContext { listening.ownerSpeechSettingChanged() }
        if force { updateFilterTerms() }
        if force || s.pauseThresholdMs != old.pauseThresholdMs || s.questionPauseMs != old.questionPauseMs {
            turns.setThreshold(s.pauseThresholdMs, questionMs: s.questionPauseMs)
        }
        turns.draftsEnabled = s.speculativeAnswers
        CustomEndpoint.shared.update(from: s)   // адрес своего API для «Проверить» (COPILOT-04 R-06)
        if !s.speculativeAnswers { answers.cancelDraft() }
        if !force && s.embeddingModel != old.embeddingModel { bank.embeddingModelChanged(s.embeddingModel) }
        if force || s.recognitionPromptFromBank != old.recognitionPromptFromBank { updateRecognitionPrompt() }
        panel.apply(s)
        answers.refreshStrongModelAvailability()
        lastSettings = s
    }

    /// Словарь терминов фильтра языка: встроенный + слова латиницей из резюме, вакансии и базы (COPILOT-05 R-05).
    private func updateFilterTerms() {
        let profile = bank.profile
        let cardTexts = bank.cards.flatMap { $0.questions + [$0.answer] }
        listening.setTerms(TermDictionary(extra: [profile.resume, profile.job, profile.stories] + cardTexts))
    }

    private func updateRecognitionPrompt() {
        guard model.settings.recognitionPromptFromBank else {
            listening.setRecognitionPrompt(nil)
            return
        }
        let cards = bank.cards
        listening.setRecognitionPrompt { language in RecognitionVocabulary.prompt(cards: cards, language: language) }
    }

    private func refreshUI() {
        var state = model.menuState(listening: listening.listeningStatus, profileName: bank.profile.name,
                                    cardCount: bank.cards.count)
        state.bankError = bank.error
        state.profiles = bank.profiles
        state.activeProfileID = bank.activeID
        state.statusLine = usage.statusLine
        state.hotkeys = model.settings.hotkeys
        state.panelVisible = panel.isVisible
        state.selfTest = listening.source == .microphone && !testCall.active && !interviewer.active
        state.ownerAnswering = listening.ownerAnswering
        state.sessionActive = liveSession.isActive
        state.sessionTimer = liveSession.clock?.elapsedText()
        menuBar?.state = state

        workspaceModel.sessionActive = liveSession.isActive
        workspaceModel.sessionTimer = liveSession.clock?.elapsedText()
        workspaceModel.recognitionStatus = listening.sttStatus
        workspaceModel.recognizerReady = listening.recognizerLoaded
        panelModel.sessionActive = liveSession.isActive
        panelModel.sessionTimer = liveSession.clock?.elapsedText()
        panelModel.planNotice = liveSession.planNotice
        panelModel.callDetected = liveSession.detectedCall

        panelModel.sourceName = listening.source.displayName
        panelModel.ownerAnswering = listening.ownerAnswering
        panelModel.selfTest = state.selfTest
        panelModel.setTranscript(listening.transcript, partial: listening.partialText)
        panelModel.autoGenerate = liveSession.isActive ? liveSession.config.autoGenerate : (model.settings.lastSessionConfig?.autoGenerate ?? true)
        panelModel.language = model.settings.language
        panelModel.sessionNotes = liveSession.notes
        // Ответы живут в истории панели и после конца сессии — общее состояние только про слушание.
        switch listening.phase {
        case .noPermission: panelModel.state = .noPermission
        case .idle: panelModel.state = .idle
        case .paused: panelModel.state = .paused
        case .standby: panelModel.state = .noSession
        case .error(let message): panelModel.state = .error(message)
        case .listening: panelModel.state = .listening
        }
        updateLevels()
    }

    // MARK: Звук в оверлее (COPILOT-09 R-08)

    private var lastCallSignalAt = Date()

    /// Уровни микрофона и звонка; «не слышу звонок N с» — только в сессии со звуком приложения (не в самопроверке).
    private func updateLevels() {
        // Шаг 3 дБ и запись только при изменении: шапка не перерисовывается 10 раз в секунду без нужды.
        let mic = (listening.micLevelDB / 3).rounded() * 3, call = (listening.levelDB / 3).rounded() * 3
        if panelModel.micLevel != mic { panelModel.micLevel = mic }
        if panelModel.callLevel != call { panelModel.callLevel = call }
        guard liveSession.isActive, listening.phase == .listening, listening.source != .microphone, liveSession.config.type != .mock else {
            if panelModel.callSilentSeconds != nil { panelModel.callSilentSeconds = nil }
            lastCallSignalAt = Date()
            return
        }
        if listening.levelDB > Preflight.callSignalDB { lastCallSignalAt = Date() }
        let silent = Int(Date().timeIntervalSince(lastCallSignalAt))
        let notice = silent >= 10 ? silent : nil
        if panelModel.callSilentSeconds != notice { panelModel.callSilentSeconds = notice }
    }

    private func turnCompleted(_ turn: Turn) {
        guard !testCall.active, !testCallOnly else { return }
        if turn.forced, panelModel.history.isRepeat(of: turn.text) {
            Log.app.info("turn \(turn.id) ignored: repeated Answer while the answer is still coming")
            return
        }
        panelModel.detection = panelModel.detection.next(on: .turnCompleted)
        memory.addQuestion(turn.text, turnID: turn.id)
        saveMemory()
        answers.handle(turn)
    }

    // MARK: Память интервью (COPILOT-06)

    let memory = InterviewMemory()
    /// Быстрый текст реплик до уточнения (R-37): по нему находим вопрос в памяти.
    private var fastText: [Int: String] = [:]

    private func saveMemory() {
        sessions.updateExchanges(memory.all)
    }

    // MARK: Сессия (COPILOT-09 R-01, R-02, R-06)

    private func showWizard() {
        guard !liveSession.isActive else { panel.show(); return }
        wizard.show()
    }

    /// Старт из мастера или из предложения «Начать сессию?».
    private func startSession(_ config: SessionConfig) {
        guard !liveSession.isActive, !testCall.active else { return }
        liveSession.start(config)
    }

    /// Сессия начата: профиль, язык, память, история, слушание и ходы. Границы интервью теперь задаёт сессия
    /// (раньше — тишина 30 мин и смена приложения звонка, COPILOT-06 R-05).
    private func sessionStarted(_ c: SessionConfig) {
        if let id = c.profileID { bank.select(id) }
        model.settings.useProfile = c.type == .interview || c.type == .mock
        if model.settings.language != c.language { model.settings.language = c.language }
        model.settings.lastSessionConfig = c.defaultsForNext()
        memory.reset()
        fastText = [:]
        answers.cancel()
        sessions.start(source: listening.source.displayName, retentionDays: model.settings.historyRetentionDays, config: c)
        turns.autoEnabled = c.autoGenerate
        panelModel.history.clear()
        panelModel.detection = panelModel.detection.next(on: .reset)
        answers.clearTask()
        // ⌘-схема ParakeetAI — только на время сессии (Q10).
        panelModel.sessionHotkeysFailed = Set(hotkeys?.registerSession() ?? [])
        if c.type == .mock {
            // ИИ-собеседование само управляет звуком (вопрос — звук браузера, ответ — микрофон).
            turns.start()
            interviewer.start()
        } else {
            listening.startSession()
            turns.start()
        }
        panel.show()
        refreshUI()
    }

    private func sessionEnded(_ c: SessionConfig) {
        hotkeys?.unregisterSession()
        panelModel.sessionHotkeysFailed = []
        answers.clearTask()
        if panelModel.chatOpen { panelModel.chatOpen = false; panel.setChatFocus(false) }
        panelModel.detection = panelModel.detection.next(on: .reset)
        turns.stop()
        answers.cancel()
        if c.type == .mock, interviewer.active { Task { await interviewer.close() } }
        listening.enterStandby()
        let record = sessions.finish()
        refreshUI()
        // Разбор (R-13, Q15): сразу после End в фоне; окно открывается на этой сессии — расшифровка видна сразу.
        if c.reviewAfterEnd, c.saveTranscript, let record, record.canBeReviewed, sessions.store.load(record.id) != nil {
            reviews.start(record.id)
            workspace.show(.sessions, select: record.id)
        }
    }

    /// Опережающий запрос (COPILOT-04 R-01): ответ готовится до истечения паузы, показывается при ходе с тем же текстом.
    private func draftReady(_ text: String) {
        guard !testCall.active, !testCallOnly else { return }
        panelModel.detection = panelModel.detection.next(on: .draftReady)
        answers.prefetch(text)
    }

    private func handle(_ action: HotkeyAction) {
        if (testCall.active || testCallOnly) && [.answerNow, .strongModel, .screenshot].contains(action) { return }
        switch action {
        case .answerNow: turns.forceTurn()
        case .togglePanel: togglePanel()
        case .togglePause: togglePause()
        case .strongModel: answers.askStrongModel()
        case .ownerAnswer: toggleOwnerAnswering()
        case .screenshot: takeScreenshot()
        case .newSession: showWizard()
        case .chat: toggleChat()
        case .clearTranscript: clearTranscript()
        case .previousAnswer: panelModel.selectPrevious()
        case .nextAnswer: panelModel.selectNext()
        }
    }

    // MARK: Оверлей (COPILOT-09 R-07…R-11, R-17)

    private func toggleChat() {
        guard liveSession.isActive else { return }
        panelModel.chatOpen.toggle()
        if panelModel.chatOpen {
            panelModel.chatMode = panelModel.history.current == nil ? .question : .refine
            if panelModel.collapsed { panel.setCollapsed(false) }
        }
        panel.setChatFocus(panelModel.chatOpen)
    }

    /// Отправка из чата: вопрос — как голосовой ход; уточнение — новая версия ответа; указание — до конца сессии.
    private func chatSubmit(_ text: String, mode: PanelModel.ChatMode) {
        switch mode {
        case .question:
            turns.answerFiltered(text)
        case .refine:
            answers.refine(text, label: String(text.prefix(24)))
        case .session:
            liveSession.addNote(text)
        }
        Log.app.info("chat submit mode=\(mode.rawValue, privacy: .public)")
        panelModel.chatOpen = false
        panel.setChatFocus(false)
        refreshUI()
    }

    /// Clear (решение владельца Q13): строка расшифровки и «последние реплики» следующего ответа; память интервью
    /// и сохранённая расшифровка остаются.
    private func clearTranscript() {
        listening.clearTranscript()
        turns.clearPending()
        answers.cancelDraft()
        answers.clearTask()
        panelModel.detection = panelModel.detection.next(on: .reset)
        Log.app.info("transcript cleared")
        refreshUI()
    }

    private func setupWorkspace() {
        wizard.onTestCall = { [weak self] in self?.handle(MenuAction.practice) }
        workspaceModel.onCreateSession = { [weak self] in self?.showWizard() }
        workspaceModel.onTestCall = { [weak self] in self?.handle(MenuAction.practice) }
        workspaceModel.onMock = { [weak self] in self?.handle(MenuAction.aiInterview) }
        workspaceModel.onShowPanel = { [weak self] in self?.panel.show() }
        workspaceModel.onEndSession = { [weak self] in self?.liveSession.end() }
        workspaceModel.onOpenPermissions = { [weak self] in self?.permissionsWindow.show() }
    }

    private func setupOverlayActions() {
        panelModel.onAnswerNow = { [weak self] in self?.turns.forceTurn() }
        panelModel.onScreenshot = { [weak self] in self?.takeScreenshot() }
        panelModel.onToggleChat = { [weak self] in self?.toggleChat() }
        panelModel.onChatSubmit = { [weak self] text, mode in self?.chatSubmit(text, mode: mode) }
        panelModel.onQuickRefine = { [weak self] chip in
            self?.answers.refine(AnswerController.quickRefinements[chip] ?? chip, label: chip.lowercased())
        }
        panelModel.onClearTranscript = { [weak self] in self?.clearTranscript() }
        panelModel.onRetryAnswer = { [weak self] id in self?.answers.retry(entry: id) }
        panelModel.onRemoveSessionNote = { [weak self] i in
            self?.liveSession.removeNote(at: i)
            self?.refreshUI()
        }
        panelModel.onToggleAuto = { [weak self] in
            guard let self else { return }
            if self.liveSession.isActive {
                self.liveSession.setAutoGenerate(!self.liveSession.config.autoGenerate)
                self.turns.autoEnabled = self.liveSession.config.autoGenerate
            } else {
                var c = self.model.settings.lastSessionConfig ?? SessionConfig()
                c.autoGenerate.toggle()
                self.model.settings.lastSessionConfig = c
            }
            self.refreshUI()
        }
        panelModel.onSelectLanguage = { [weak self] lang in self?.model.settings.language = lang }
        panelModel.onZoom = { [weak self] step in
            guard let self else { return }
            let z = step == 0 ? 1 : self.model.settings.panelZoom + Double(step) * 0.1
            self.model.settings.panelZoom = min(max(z, AppSettings.panelZoomRange.lowerBound), AppSettings.panelZoomRange.upperBound)
        }
        panelModel.onNextScreen = { [weak self] in self?.panel.moveToNextScreen() }
        panelModel.onToggleCollapse = { [weak self] in
            guard let self else { return }
            self.panel.setCollapsed(!self.panelModel.collapsed)
        }
        panelModel.onTogglePrivate = { [weak self] in
            guard let self else { return }
            self.model.settings.panelHiddenFromCapture.toggle()
            self.panelModel.visibilityResult = nil
        }
        panelModel.onCheckVisibility = { [weak self] in
            guard let self else { return }
            self.panelModel.checkingVisibility = true
            Task {
                self.panelModel.visibilityResult = await self.panel.checkVisibility()
                self.panelModel.checkingVisibility = false
            }
        }
        panelModel.onOwnerAnswer = { [weak self] in self?.toggleOwnerAnswering() }
    }

    /// ⌃⌥A или пункт меню «Сейчас отвечаю я» (самопроверка, COPILOT-06/07).
    private func toggleOwnerAnswering() {
        if !listening.toggleOwnerAnswering() { Log.app.info("owner answer ignored: not self-test source") }
        refreshUI()
    }

    /// ⌃⌥S — снимок задачи → сильная модель (без ключа Anthropic — Gemini), S-06.
    private func takeScreenshot() {
        let settings = model.settings
        let secrets = model.secrets
        let language = listening.transcript.last?.language ?? settings.language.whisperCode
        panel.show()
        Task {
            do {
                let started = TurnController.now()
                let jpeg = try await ScreenshotService.captureDisplayUnderCursor()
                Log.metrics.notice("screenshot_captured bytes=\(jpeg.count) ms=\(Int(TurnController.now() - started))")
                let chain = await Task.detached {
                    ChainFactory.strong(settings: settings, secrets: secrets, providers: ChainFactory.providers(), fallbackToGemini: true)
                }.value
                guard let chain else {
                    screenshotFailed("Нет ключа ни для сильной модели, ни для Gemini")
                    return
                }
                answers.screenshot(jpeg, chain: chain, language: language)
            } catch {
                screenshotFailed("Скриншот не получился: \(error)")
            }
        }
    }

    /// Ошибка скриншота — в истории ответов отдельным вопросом с причиной, слушание не прерывается.
    private func screenshotFailed(_ reason: String) {
        let ids = panelModel.history.begin(question: "Скриншот задачи", turnID: nil, kind: .screenshot)
        panelModel.history.update(entry: ids.entry, version: ids.version) { $0.status = .failed(reason) }
    }

    /// Прогресс загрузки моделей — в панель (состояние downloading, R-16).
    private func startDownloadProgressMirror() {
        Task { [weak self] in
            while let self {
                try? await Task.sleep(for: .milliseconds(300))
                if let p = self.onboarding.state.overallProgress {
                    self.panelModel.state = .downloading(p)
                } else if case .downloading = self.panelModel.state {
                    self.panelModel.state = .idle
                    self.refreshUI()
                }
            }
        }
    }

    private func togglePanel() {
        panel.toggle()
        refreshUI()
    }

    private func togglePause() {
        guard liveSession.isActive else { return }   // без сессии ставить на паузу нечего (COPILOT-09 R-02)
        let pausing = listening.phase == .listening
        listening.togglePause()
        if pausing {
            // S-08: при паузе ничего не отправляется — текущая генерация отменяется.
            answers.cancel()
            turns.stop()
        } else if !testCall.active && !testCallOnly {
            turns.start()
        }
    }

    private func handle(_ action: MenuAction) {
        if (testCall.active || testCallOnly) && [.answerNow, .screenshot].contains(action) { return }
        switch action {
        case .practice:
            guard !interviewer.active else { return }
            testCall.start()
        case .aiInterview:
            // ИИ-собеседование — сессия типа Mock с последними настройками (COPILOT-09 R-06).
            guard !testCall.active, !liveSession.isActive else { return }
            var c = wizard.defaultConfig()
            c.type = .mock
            startSession(c)
        case .settings:
            workspace.show(.settings)
        case .quit:
            NSApp.terminate(nil)
        case .togglePause:
            togglePause()
        case .sessionHistory:
            workspace.show(.sessions)
        case .newSession:
            showWizard()
        case .endSession:
            liveSession.end()
        case .ownerAnswer:
            toggleOwnerAnswering()
        case .togglePanel:
            togglePanel()
        case .answerNow:
            turns.forceTurn()
        case .screenshot:
            takeScreenshot()
        case .listeningSource:
            permissionsWindow.show()
        case .questionBank:
            bank.openQuestions()
        case .editProfile, .profile:
            workspace.show(.profiles)
        default:
            // Остальные действия подключаются на шагах P-06…P-10.
            break
        }
    }
}
