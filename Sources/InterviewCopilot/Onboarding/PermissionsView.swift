import AppKit
import CopilotCore
import SwiftUI

/// Разрешения — S-09 (часть «разрешения»), AC-13. Приложение само ничего не меняет в TCC: только показывает статус
/// и открывает нужный раздел Системных настроек.
@MainActor
final class PermissionsWindowController {
    private var window: NSWindow?
    private let listening: ListeningController

    init(listening: ListeningController) {
        self.listening = listening
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: PermissionsView(listening: listening).localizedRoot()))
            UILanguage.shared.setTitle("Interview Copilot — разрешения", of: w)
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct PermissionsView: View {
    let listening: ListeningController
    @State private var screenGranted = Permissions.screenCaptureGranted
    @State private var mic = Permissions.microphone
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Чтобы слышать собеседника, нужны разрешения macOS.")
                .font(.headline)

            PermissionRow(
                granted: screenGranted,
                title: "Запись экрана и системного звука",
                detail: "Обязательно: через неё приложение получает звук Meet, Zoom или Telegram. Экран не записывается.",
                primaryTitle: screenGranted ? nil : "Запросить",
                primaryAction: requestScreen,
                openSettings: { NSWorkspace.shared.open(Permissions.screenCaptureSettingsURL) }
            )
            PermissionRow(
                granted: mic == .granted,
                title: "Микрофон",
                detail: "Нужен только чтобы понять, что вы говорите сами (тогда подсказка не мешает). Ваш голос не расшифровывается и не сохраняется.",
                primaryTitle: mic == .notDetermined ? "Разрешить" : nil,
                primaryAction: requestMic,
                openSettings: { NSWorkspace.shared.open(Permissions.microphoneSettingsURL) }
            )

            if !screenGranted {
                Label("Без этого разрешения слушать нельзя. После включения переключателя macOS попросит перезапустить приложение.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            Divider()
            HStack {
                Circle().fill(dotColor).frame(width: 10, height: 10).accessibilityHidden(true)
                Text(statusText)
                Spacer()
                Text("Уровень: \(listening.levelDB > -119 ? String(format: "%.0f dB", listening.levelDB) : "—")")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if listening.ownerSpeaking {
                    Label("Вы говорите", systemImage: "mic.fill").foregroundStyle(.secondary)
                }
            }
            .font(.callout)

            VStack(alignment: .leading, spacing: 4) {
                Text(listening.sttStatus).font(.caption).foregroundStyle(.secondary)
                ForEach(listening.transcript.suffix(3)) { line in
                    Text("\(line.language.uppercased()): \(line.text)").font(.callout).lineLimit(2)
                }
                if let partial = listening.partialText {
                    Text(partial + " ▍").font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            }

            HStack {
                Spacer()
                Button("Перезапустить приложение") { Relauncher.relaunch() }
                Button("Проверить снова") { refresh(); listening.start() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onReceive(timer) { _ in refresh() }
    }

    private var statusText: String {
        switch listening.phase {
        case .noPermission: "Нет разрешения на запись экрана"
        case .idle: "Источник не найден: откройте Meet в Chrome, Zoom или Telegram"
        case .listening: L("Слушаю: %@", listening.source.displayName ?? "—")
        case .paused: "Пауза"
        case .standby: "Сессии нет — приложение не слушает. Создайте сессию в меню"
        case .error(let message): L("Ошибка: %@", message)
        }
    }

    private var dotColor: Color {
        switch listening.phase {
        case .listening: .green
        case .noPermission, .error: .red
        default: .gray
        }
    }

    private func requestScreen() {
        Permissions.requestScreenCapture()
        refresh()
    }

    private func requestMic() {
        Task {
            _ = await Permissions.requestMicrophone()
            refresh()
        }
    }

    private func refresh() {
        screenGranted = Permissions.screenCaptureGranted
        mic = Permissions.microphone
    }
}

private struct PermissionRow: View {
    let granted: Bool
    let title: String
    let detail: String
    let primaryTitle: String?
    let primaryAction: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
                .font(.title2)
                .accessibilityLabel(granted ? "Разрешено" : "Не разрешено")
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !granted {
                    HStack {
                        if let primaryTitle { Button(primaryTitle, action: primaryAction) }
                        Button("Открыть Системные настройки", action: openSettings)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

enum Relauncher {
    /// Перезапуск: после выдачи «Записи экрана» macOS применяет разрешение только к новому процессу.
    @MainActor
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}
