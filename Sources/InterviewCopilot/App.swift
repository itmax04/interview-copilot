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
    private let panelModel = PanelModel()
    private lazy var panel = PanelController(model: panelModel)
    private lazy var turns = TurnController(thresholdMs: model.settings.pauseThresholdMs)
    private var hotkeys: HotkeyCenter?
    private var lastSettings: AppSettings?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        let menuBar = MenuBarController(onAction: { [weak self] action in self?.handle(action) })
        menuBar.sourceMenuData = { [weak self] in
            (self?.model.settings.audioSource ?? .auto, ListeningController.runningApps())
        }
        menuBar.onSelectSource = { [weak self] value in self?.model.settings.audioSource = value }
        self.menuBar = menuBar

        hotkeys = HotkeyCenter { [weak self] action in self?.handle(action) }
        lastSettings = model.settings
        applySettings(force: true)

        model.onChange = { [weak self] in self?.settingsChanged() }
        listening.onChange = { [weak self] in self?.refreshUI() }
        listening.onTranscript = { [weak self] event in self?.turns.handle(event) }
        listening.onOwnerSpeaking = { [weak self] speaking, t in self?.turns.ownerSpeaking(speaking, at: t) }
        turns.onTurn = { [weak self] turn in self?.turnCompleted(turn) }

        panelModel.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        panelModel.onOpenPermissions = { [weak self] in self?.permissionsWindow.show() }
        panelModel.onRetry = { [weak self] in self?.listening.start() }

        listening.start()
        turns.start()
        refreshUI()
        panel.show()
        if listening.phase == .noPermission {
            // AC-13: без разрешения — понятное состояние и инструкция, без падения.
            permissionsWindow.show()
        }
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
        panel.apply(s)
        lastSettings = s
    }

    private func refreshUI() {
        var state = model.menuState(listening: listening.listeningStatus)
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
        panelModel.question = turn.text
        // Ответ по базе и генерация подключаются на P-06…P-08.
    }

    private func handle(_ action: HotkeyAction) {
        switch action {
        case .answerNow: turns.forceTurn()
        case .togglePanel: togglePanel()
        case .togglePause: togglePause()
        case .screenshot, .strongModel: break // P-09, P-08
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
        case .togglePanel:
            togglePanel()
        case .answerNow:
            turns.forceTurn()
        case .listeningSource:
            permissionsWindow.show()
        default:
            // Остальные действия подключаются на шагах P-06…P-10.
            break
        }
    }
}
