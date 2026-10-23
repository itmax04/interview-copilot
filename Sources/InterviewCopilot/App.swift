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
        if args.contains("--smoke-llm") {
            setvbuf(stdout, nil, _IOLBF, 0)
            exit(SmokeTest.run())
        }

        let app = NSApplication.shared
        let delegate = AppDelegate(testCallOnly: args.contains("--test-call"), openInterviewer: args.contains("--ai-interview"),
                                   openSettings: args.contains("--settings"))
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
    init(testCallOnly: Bool = false, openInterviewer: Bool = false, openSettings: Bool = false) {
        self.testCallOnly = testCallOnly
        self.openInterviewer = openInterviewer && !testCallOnly
        self.openSettings = openSettings
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
    })
    private lazy var permissionsWindow = PermissionsWindowController(listening: listening)
    private lazy var onboarding: OnboardingWindowController = makeOnboarding()

    private func makeOnboarding() -> OnboardingWindowController {
        OnboardingWindowController(model: model, listening: listening) { [weak self] in
            self?.onboarding.close()
            self?.listening.start()
        }
    }
    private let panelModel = PanelModel()
    private lazy var panel = PanelController(model: panelModel)
    private lazy var turns = TurnController(thresholdMs: model.settings.pauseThresholdMs)
    private let bank = BankController()
    private lazy var answers = AnswerController(model: model, bank: bank, panel: panelModel)
    private let sessions = SessionController()
    private lazy var historyWindow = SessionHistoryWindowController(sessions: sessions)
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
        menuBar.onSelectStrongModel = { [weak self] p in self?.model.settings.strongProvider = p }
        menuBar.providersWithKeys = { [weak self] in
            Set(ProviderID.allCases.filter { self?.model.hasKey[$0] == true })
        }
        menuBar.strongProvider = { [weak self] in self?.model.settings.strongProvider ?? .anthropic }
        self.menuBar = menuBar

        hotkeys = HotkeyCenter { [weak self] action in self?.handle(action) }
        lastSettings = model.settings
        applySettings(force: true)

        model.onChange = { [weak self] in self?.settingsChanged() }
        listening.onChange = { [weak self] in self?.refreshUI() }
        listening.onTranscript = { [weak self] event in
            guard let self else { return }
            if self.testCall.active { self.testCall.handleTranscript(event); return }
            guard !self.testCallOnly else { return }
            // ИИ-собеседование: вопрос сверяется с текстом модели и при этом идёт в обычные подсказки, как на созвоне.
            if self.interviewer.active { self.interviewer.handleCallTranscript(event) }
            self.turns.handle(event)
            if case .final(let u, let text, let lang, _, _) = event { self.sessions.addUtterance(id: u, text: text, language: lang) }
            if case .revised(let u, let text, let lang) = event { self.sessions.reviseUtterance(id: u, text: text, language: lang) }
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
            } else if self.listening.phase != .paused { self.turns.start() }
            self.refreshUI()
        }
        testCall.onPermissions = { [weak self] in self?.permissionsWindow.show() }
        listening.onOwnerTranscript = { [weak self] event in self?.interviewer.handleOwnerTranscript(event) }
        interviewer.onEnd = { [weak self] in self?.refreshUI() }
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

        panelModel.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        panelModel.onOpenPermissions = { [weak self] in self?.permissionsWindow.show() }
        panelModel.onRetry = { [weak self] in self?.listening.start() }

        bank.onChange = { [weak self] in
            self?.updateRecognitionPrompt()
            self?.updateFilterTerms()
            self?.refreshUI()
        }
        // В промпт — только реплики интервьюера, прошедшие фильтры (серые строки COPILOT-05 не идут).
        answers.transcript = { [weak self] in self?.listening.transcript.filter { $0.filtered == nil }.map(\.text) ?? [] }
        answers.candidateSaid = { [weak self] in self?.listening.candidateSaid ?? [] }
        answers.onUsage = { [weak self] provider, modelID, u in self?.recordUsage(provider, modelID, u) }
        answers.onProviderError = { [weak self] provider, error in
            self?.usage.recordError(provider: provider, error: error)
            self?.refreshUI()
        }
        answers.onAnswer = { [weak self] record in
            guard let self else { return }
            self.sessions.addAnswer(record)
            // COPILOT-06: подсказка — в обмен этого вопроса (для разбора после звонка).
            if !record.text.isEmpty { self.memory.setHint(record.text, forQuestion: record.turn.text); self.saveMemory() }
        }
        // COPILOT-06: память интервью вместо отдельного блока «что кандидат сказал» — ответы уже в обменах.
        answers.memory = memory
        answers.embed = { [weak self] in self?.bank.embedFunction }
        answers.candidateSaid = { [] }
        listening.onOwnerSaid = { [weak self] text in
            self?.memory.addAnswer(text)
            self?.saveMemory()
        }
        if testCallOnly {
            testCall.start()
            refreshUI()
            return
        }
        sessions.start(source: nil, retentionDays: model.settings.historyRetentionDays)
        bank.start(embeddingModel: model.settings.embeddingModel)

        listening.start()
        turns.start()
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
        if openInterviewer { interviewer.start() }
        if openSettings { settingsWindow.show() }
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
        applySettings(force: false)
        refreshUI()
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
        checkCallSourceChange()
        var state = model.menuState(listening: listening.listeningStatus, profileName: bank.profile.name,
                                    cardCount: bank.cards.count)
        state.bankError = bank.error
        state.statusLine = usage.statusLine
        state.hotkeys = model.settings.hotkeys
        state.panelVisible = panel.isVisible
        menuBar?.state = state

        panelModel.sourceName = listening.source.displayName
        panelModel.setTranscript(listening.transcript, partial: listening.partialText)
        switch listening.phase {
        case .noPermission: panelModel.state = .noPermission
        case .idle: panelModel.state = .idle
        case .paused: panelModel.state = .paused
        case .error(let message): panelModel.state = .error(message)
        case .listening:
            // Ответ, «нет в базе» и генерация остаются на экране; остальные состояния сменяются на «слушаю».
            switch panelModel.state {
            case .thinking, .answer, .noMatch: break
            default: panelModel.state = .listening
            }
        }
    }

    private func turnCompleted(_ turn: Turn) {
        guard !testCall.active, !testCallOnly else { return }
        // COPILOT-06: тишина дольше 30 минут — это уже другое интервью.
        if let last = lastTurnAt, Date().timeIntervalSince(last) > Self.newInterviewAfterSilence { startNewInterview(reason: "silence") }
        lastTurnAt = Date()
        memory.addQuestion(turn.text)
        saveMemory()
        answers.handle(turn)
    }

    // MARK: Память интервью (COPILOT-06)

    let memory = InterviewMemory()
    private var lastTurnAt: Date?
    private var lastCallSource: String?
    static let newInterviewAfterSilence: TimeInterval = 30 * 60

    private func saveMemory() {
        sessions.updateExchanges(memory.all)
    }

    /// Новое интервью: прошлое сохраняется в историю, память очищается (R-06 COPILOT-06).
    func startNewInterview(reason: String) {
        sessions.finish()
        memory.reset()
        listening.clearCandidateContext()
        lastTurnAt = nil
        sessions.start(source: listening.source.displayName, retentionDays: model.settings.historyRetentionDays)
        Log.app.info("new interview: \(reason, privacy: .public)")
        refreshUI()
    }

    /// Смена приложения звонка (например, Zoom → Telegram) — новое интервью.
    private func checkCallSourceChange() {
        let name: String? = switch listening.source {
        case .app(let app): app.bundleID
        case .allSystem: "all-system"
        default: nil
        }
        guard let name else { return }
        if let previous = lastCallSource, previous != name, !memory.all.isEmpty { startNewInterview(reason: "source") }
        lastCallSource = name
    }

    /// Опережающий запрос (COPILOT-04 R-01): ответ готовится до истечения паузы, показывается при ходе с тем же текстом.
    private func draftReady(_ text: String) {
        guard !testCall.active, !testCallOnly else { return }
        answers.prefetch(text)
    }

    private func handle(_ action: HotkeyAction) {
        if (testCall.active || testCallOnly) && [.answerNow, .strongModel, .screenshot].contains(action) { return }
        switch action {
        case .answerNow: turns.forceTurn()
        case .togglePanel: togglePanel()
        case .togglePause: togglePause()
        case .strongModel: answers.askStrongModel()
        case .screenshot: takeScreenshot()
        }
    }

    /// ⌃⌥S — снимок задачи → сильная модель (без ключа Anthropic — Gemini), S-06.
    private func takeScreenshot() {
        let settings = model.settings
        let secrets = model.secrets
        let language = listening.transcript.last?.language ?? settings.language.whisperCode
        panelModel.question = "Скриншот задачи"
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
                    panelModel.state = .error("Нет ключа ни для сильной модели, ни для Gemini")
                    return
                }
                let turn = Turn(id: -1, text: "Скриншот задачи", speechEndedAt: started, firedAt: started, forced: true)
                answers.showGenerated(chain: chain, request: PromptBuilder.screenshotRequest(image: jpeg, language: language), label: turn)
            } catch {
                panelModel.state = .error("\(error)")
            }
        }
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
            guard !testCall.active else { return }
            interviewer.start()
        case .settings:
            settingsWindow.show()
        case .quit:
            NSApp.terminate(nil)
        case .togglePause:
            togglePause()
        case .sessionHistory:
            historyWindow.show()
        case .newInterview:
            startNewInterview(reason: "menu")
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
            bank.openProfileFolder()
        default:
            // Остальные действия подключаются на шагах P-06…P-10.
            break
        }
    }
}
