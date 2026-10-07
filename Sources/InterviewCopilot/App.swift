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
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
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
            self?.turns.handle(event)
            if case .final(let u, let text, let lang, _, _) = event { self?.sessions.addUtterance(id: u, text: text, language: lang) }
        }
        listening.onOwnerSpeaking = { [weak self] speaking, t in self?.turns.ownerSpeaking(speaking, at: t) }
        turns.onTurn = { [weak self] turn in self?.turnCompleted(turn) }

        panelModel.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        panelModel.onOpenPermissions = { [weak self] in self?.permissionsWindow.show() }
        panelModel.onRetry = { [weak self] in self?.listening.start() }

        bank.onChange = { [weak self] in
            self?.updateRecognitionPrompt()
            self?.refreshUI()
        }
        answers.transcript = { [weak self] in self?.listening.transcript.map(\.text) ?? [] }
        answers.onUsage = { [weak self] provider, modelID, u in
            guard let self else { return }
            let s = self.model.settings
            if self.usage.record(provider: provider, model: modelID, usage: u, settings: s), !s.paidProvidersSuspended {
                // Лимит месяца: платные провайдеры выключаются до подтверждения владельцем (R-18 Budget).
                self.model.settings.paidProvidersSuspended = true
                Log.app.notice("monthly budget reached, paid providers suspended")
            }
            self.refreshUI()
        }
        answers.onProviderError = { [weak self] provider, error in
            self?.usage.recordError(provider: provider, error: error)
            self?.refreshUI()
        }
        answers.onAnswer = { [weak self] record in self?.sessions.addAnswer(record) }
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
        if !force && s.language != old.language { listening.languageSettingChanged() }
        if force || s.pauseThresholdMs != old.pauseThresholdMs { turns.setThreshold(s.pauseThresholdMs) }
        if !force && s.embeddingModel != old.embeddingModel { bank.embeddingModelChanged(s.embeddingModel) }
        if force || s.recognitionPromptFromBank != old.recognitionPromptFromBank { updateRecognitionPrompt() }
        panel.apply(s)
        answers.refreshStrongModelAvailability()
        lastSettings = s
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
        answers.handle(turn)
    }

    private func handle(_ action: HotkeyAction) {
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
        if pausing { turns.stop() } else { turns.start() }
    }

    private func handle(_ action: MenuAction) {
        switch action {
        case .settings:
            settingsWindow.show()
        case .quit:
            NSApp.terminate(nil)
        case .togglePause:
            togglePause()
        case .sessionHistory:
            historyWindow.show()
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
