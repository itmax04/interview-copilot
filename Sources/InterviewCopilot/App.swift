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
    private lazy var settingsWindow = SettingsWindowController(model: model)
    private lazy var permissionsWindow = PermissionsWindowController(listening: listening)
    private var lastAudioSource: AudioSourceSetting?
    private var lastLanguage: RecognitionLanguage?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        let menuBar = MenuBarController(onAction: { [weak self] action in self?.handle(action) })
        menuBar.sourceMenuData = { [weak self] in
            (self?.model.settings.audioSource ?? .auto, ListeningController.runningApps())
        }
        menuBar.onSelectSource = { [weak self] value in self?.model.settings.audioSource = value }
        self.menuBar = menuBar
        lastAudioSource = model.settings.audioSource
        lastLanguage = model.settings.language

        model.onChange = { [weak self] in
            guard let self else { return }
            if self.model.settings.audioSource != self.lastAudioSource {
                self.lastAudioSource = self.model.settings.audioSource
                self.listening.sourceSettingChanged()
            }
            if self.model.settings.language != self.lastLanguage {
                self.lastLanguage = self.model.settings.language
                self.listening.languageSettingChanged()
            }
            self.refreshMenu()
        }
        listening.onChange = { [weak self] in self?.refreshMenu() }
        refreshMenu()

        listening.start()
        if listening.phase == .noPermission {
            // AC-13: без разрешения — понятное состояние и инструкция, без падения.
            permissionsWindow.show()
        }
    }

    private func refreshMenu() {
        menuBar?.state = model.menuState(listening: listening.listeningStatus)
    }

    private func handle(_ action: MenuAction) {
        switch action {
        case .settings:
            settingsWindow.show()
        case .quit:
            NSApp.terminate(nil)
        case .togglePause:
            listening.togglePause()
        case .listeningSource:
            permissionsWindow.show()
        default:
            // Остальные действия подключаются на шагах P-05…P-10.
            break
        }
    }
}
