import CopilotCore
import SwiftUI

/// Содержимое панели — R-16: шапка, «Interviewer», карточка ответа, подвал.
struct PanelView: View {
    @Bindable var model: PanelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider().overlay(Color.white.opacity(0.15))
            content
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .foregroundStyle(.white)
        .font(.system(size: model.fontSize))
        .frame(minWidth: 300, maxWidth: .infinity, minHeight: 220, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Шапка

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: ParrotIcon.colored(size: 20))
                .accessibilityHidden(true)
            StatusPill(state: model.state, source: model.sourceName)
            Spacer()
            if let badge = model.badge {
                Text(badge)
                    .font(.system(size: model.fontSize - 2, weight: .semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .accessibilityLabel("Источник: \(badge)")
            }
            if let latency = model.latency {
                Text(String(format: "%.1fs", latency))
                    .font(.system(size: model.fontSize - 2).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
                    .accessibilityLabel(String(format: "Задержка %.1f секунды", latency))
            }
        }
    }

    // MARK: Содержимое по состоянию

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            Message(icon: "ear", text: "Выберите источник: откройте созвон в Chrome, Zoom или Telegram или выберите приложение в меню «Listening».")
        case .noPermission:
            VStack(alignment: .leading, spacing: 10) {
                Message(icon: "lock.shield", text: "Нет разрешения «Запись экрана и системного звука» — без него слушать нельзя.")
                Button("Открыть Системные настройки") { model.onOpenPermissions?() }
                    .accessibilityHint("Открывает раздел разрешений")
            }
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 8) {
                Text("Загрузка моделей распознавания…")
                ProgressView(value: progress)
                    .accessibilityLabel("Прогресс загрузки \(Int(progress * 100)) процентов")
            }
        case .error(let message):
            VStack(alignment: .leading, spacing: 10) {
                Message(icon: "exclamationmark.triangle", text: message)
                HStack {
                    Button("Открыть настройки") { model.onOpenSettings?() }
                    Button("Повторить") { model.onRetry?() }
                }
            }
        default:
            InterviewerView(model: model, reduceMotion: reduceMotion)
            AnswerArea(model: model)
        }
    }

    // MARK: Подвал

    private var footer: some View {
        HStack(spacing: 14) {
            FooterHint(keys: model.hotkey(.answerNow), label: "ответ")
            FooterHint(keys: model.hotkey(.screenshot), label: "скриншот")
            FooterHint(keys: model.hotkey(.togglePanel), label: "скрыть")
        }
        .font(.system(size: max(10, model.fontSize - 3)))
        .foregroundStyle(.white.opacity(0.7))
    }
}

private struct StatusPill: View {
    let state: PanelModel.State
    let source: String?

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(text).lineLimit(1)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.12)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Статус: \(text)")
    }

    private var text: String {
        switch state {
        case .listening, .answer, .noMatch: "Listening — \(source ?? "—")"
        case .paused: "Paused"
        case .thinking: "Thinking…"
        case .idle: "Idle"
        case .noPermission: "No permission"
        case .downloading: "Downloading"
        case .error: "Error"
        }
    }

    private var color: Color {
        switch state {
        case .listening, .answer, .noMatch, .thinking: .green
        case .paused, .idle, .downloading: .gray
        case .noPermission, .error: .red
        }
    }
}

private struct InterviewerView: View {
    let model: PanelModel
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Interviewer")
                .font(.system(size: model.fontSize - 3, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)
            if model.ownerAnswering {
                // COPILOT-06: самопроверка — речь сейчас записывается как ваш ответ.
                Label("Ваш ответ записывается — ⌃⌥A, чтобы закончить", systemImage: "mic.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Идёт запись вашего ответа. Control Option A — закончить")
            }
            if model.lines.isEmpty && model.partial == nil {
                Text(model.state == .paused ? "Пауза: ничего не слушаю и не отправляю." : "Жду, когда собеседник заговорит…")
                    .foregroundStyle(.white.opacity(0.6))
            }
            ForEach(model.lines) { line in
                if let reason = line.filtered {
                    // COPILOT-05 R-06, S-08: отфильтрованное — серым; клик — ответить всё равно.
                    Button { model.onAnswerFiltered?(line.text) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.text).italic()
                                .foregroundStyle(.white.opacity(0.35))
                                .fixedSize(horizontal: false, vertical: true)
                            Text("игнорировано: \(reason) · нажмите или ⌃⌥↩, чтобы ответить")
                                .font(.system(size: model.fontSize - 4))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Игнорировано, \(reason): \(line.text). Ответить")
                } else {
                    Text(line.text)
                        .foregroundStyle(.white.opacity(line.id == model.lines.last?.id && model.partial == nil ? 0.95 : 0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let partial = model.partial {
                (Text(partial) + Text(" ▍").foregroundColor(.white.opacity(0.6)))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Говорит: \(partial)")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct Message: View {
    let icon: String
    let text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
        }
        .foregroundStyle(.white.opacity(0.85))
    }
}

private struct FooterHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(keys).fontWeight(.semibold)
            Text(label)
        }
        .accessibilityElement(children: .combine)
    }
}
