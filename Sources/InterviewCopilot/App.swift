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
    private var menuBar: MenuBarController?
    private let settingsWindow = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController(onAction: { [weak self] action in self?.handle(action) })
    }

    private func handle(_ action: MenuAction) {
        switch action {
        case .settings:
            settingsWindow.show()
        case .quit:
            NSApp.terminate(nil)
        default:
            // Остальные действия подключаются на шагах P-03…P-10.
            break
        }
    }
}
