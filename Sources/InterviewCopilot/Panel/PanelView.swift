import CopilotCore
import SwiftUI

/// Живой оверлей — COPILOT-09 R-07…R-11, R-17: панель действий, строка расшифровки, статус вопроса, карточка ответа
/// с историей, чат. Раскладка — по исследованию ParakeetAI, оформление — целевой стиль (`Theme`, тёмное стекло).
struct PanelView: View {
    @Bindable var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toolbar(model: model)
            if !model.collapsed {
                notes
                banners
                content
                Spacer(minLength: 0)
                if model.chatOpen { ChatField(model: model) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, model.collapsed ? 12 : 12)
        .foregroundStyle(.white)
        .font(.system(size: model.fontSize))
        .frame(minWidth: 300, maxWidth: .infinity, minHeight: model.collapsed ? 0 : 220, maxHeight: .infinity, alignment: .topLeading)
        .overlay {
            // Проверка видимости (R-17): контрольный цвет на долю секунды — по нему видно, попал ли оверлей в захват экрана.
            if model.visibilityProbe { Color(red: 1, green: 0, blue: 1) }
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var notes: some View {
        if !model.sessionNotes.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(model.sessionNotes.enumerated()), id: \.offset) { i, note in
                    Button { model.onRemoveSessionNote?(i) } label: {
                        Label("На всю сессию: \(note)", systemImage: "xmark").labelStyle(TrailingIconLabel())
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: model.fontSize - 3, weight: .medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.accent.opacity(0.35)))
                    .help("Снять указание")
                }
            }
        }
    }

    @ViewBuilder private var banners: some View {
        if let notice = model.planNotice {
            Banner(icon: "clock.badge.exclamationmark", text: notice, color: Theme.warn, size: model.fontSize)
        }
        if let silent = model.callSilentSeconds, silent >= 10 {
            Banner(icon: "speaker.slash", text: "Не слышу звонок \(silent) с — проверьте звук вкладки или источник", color: Theme.warn,
                   size: model.fontSize)
        }
        if model.ownerAnswering {
            Banner(icon: "mic.fill", text: "Ваш ответ записывается — \(model.hotkey(.ownerAnswer)), чтобы закончить", color: Theme.warn,
                   size: model.fontSize)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .noSession:
            NoSessionView(model: model)
            if model.history.current != nil { AnswerCard(model: model) }
        case .idle:
            Message(icon: "ear", text: "Выберите источник: откройте созвон в Chrome, Zoom или Telegram или выберите приложение в меню «Listening».")
        case .noPermission:
            VStack(alignment: .leading, spacing: 10) {
                Message(icon: "lock.shield", text: "Нет разрешения «Запись экрана и системного звука» — без него слушать нельзя.")
                Button("Открыть Системные настройки") { model.onOpenPermissions?() }
            }
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 8) {
                Text("Загрузка моделей распознавания…")
                ProgressView(value: progress).accessibilityLabel("Прогресс загрузки \(Int(progress * 100)) процентов")
            }
        case .error(let message):
            VStack(alignment: .leading, spacing: 10) {
                Message(icon: "exclamationmark.triangle", text: message)
                HStack {
                    Button("Открыть настройки") { model.onOpenSettings?() }
                    Button("Повторить") { model.onRetry?() }
                }
            }
            if model.history.current != nil { AnswerCard(model: model) }
        case .listening, .paused:
            TranscriptStrip(model: model)
            if !model.taskImages.isEmpty { TaskChip(model: model) }
            DetectionChip(model: model)
            if model.history.current != nil { AnswerCard(model: model) }
        }
    }
}

/// Активная задача со скриншота (COPILOT-09 R-15): миниатюры, число снимков, ✕ — закрыть задачу.
private struct TaskChip: View {
    let model: PanelModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(model.taskImages.enumerated()), id: \.offset) { _, data in
                if let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 38, height: 26).clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.25)))
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Задача · \(model.taskImages.count) \(model.taskImages.count == 1 ? "снимок" : "снимка")")
                    .font(.system(size: max(10, model.fontSize - 3), weight: .semibold))
                Text(model.taskSolved ? "Уточнения голосом — к этой задаче" : "Решаю… снимок за 30 с добавится сюда")
                    .font(.system(size: max(9, model.fontSize - 4))).foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            Button { model.onCloseTask?() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .help("Закрыть задачу: вопросы больше не относятся к ней")
                .accessibilityLabel("Закрыть задачу")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.22)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: Панель действий

private struct Toolbar: View {
    let model: PanelModel

    /// Две строки: статус и управление сессией сверху, действия — во всю ширину снизу (панель узкая, 380 pt).
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                if model.sessionActive {
                    LevelBars(level: model.micLevel, icon: "mic.fill", label: "Микрофон")
                    LevelBars(level: model.callLevel, icon: "speaker.wave.2.fill", label: "Звук звонка")
                    if let timer = model.sessionTimer {
                        Text(timer)
                            .font(.system(size: model.fontSize - 2, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.leading, 4)
                            .accessibilityLabel("Время сессии \(timer)")
                    }
                } else {
                    Image(nsImage: ParrotIcon.colored(size: 18)).accessibilityHidden(true)
                    StatusPill(text: statusText, color: statusColor)
                }
                Spacer(minLength: 4)
                IconButton(symbol: model.collapsed ? "chevron.down" : "chevron.up", label: model.collapsed ? "Развернуть" : "Свернуть") {
                    model.onToggleCollapse?()
                }
                OverlayMenu(model: model)
                if model.sessionActive {
                    Button("Завершить") { model.onEndSession?() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.danger)
                        .controlSize(.small)
                        .fixedSize()
                        .accessibilityHint("Завершить сессию: приложение перестанет слушать")
                }
            }
            if model.sessionActive && !model.collapsed {
                HStack(spacing: 6) {
                    ActionButton(title: "Ответ", keys: model.hotkey(.answerNow), size: model.fontSize) { model.onAnswerNow?() }
                        .help("Ответить на последнюю реплику сейчас")
                    ActionButton(title: "Скриншот", keys: model.hotkey(.screenshot), size: model.fontSize) { model.onScreenshot?() }
                        .help("Снимок экрана с задачей → решение")
                    ActionButton(title: "Чат", keys: model.hotkey(.chat), size: model.fontSize) { model.onToggleChat?() }
                        .help("Вопрос текстом или уточнение ответа")
                    if model.selfTest {
                        ActionButton(title: model.ownerAnswering ? "Конец" : "Я отвечаю", keys: model.hotkey(.ownerAnswer),
                                     size: model.fontSize) { model.onOwnerAnswer?() }
                    }
                }
            }
        }
    }

    private var statusText: String {
        switch model.state {
        case .noSession: "Нет сессии"
        case .listening: "Слушаю — \(model.sourceName ?? "—")"
        case .paused: "Пауза"
        case .idle: "Источник не выбран"
        case .noPermission: "Нет разрешения"
        case .downloading: "Загрузка моделей"
        case .error: "Ошибка"
        }
    }

    private var statusColor: Color {
        switch model.state {
        case .listening: Theme.ok
        case .noPermission, .error: Theme.danger
        default: .gray
        }
    }
}

private struct ActionButton: View {
    let title: String
    let keys: String
    let size: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).fontWeight(.semibold)
                Text(keys).font(.system(size: max(9, size - 4), weight: .medium)).foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .font(.system(size: max(11, size - 2)))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Color.white.opacity(0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(keys)")
    }
}

private struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 22, height: 22).background(Circle().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct LevelBars: View {
    let level: Float
    let icon: String
    let label: String
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
            ForEach(Array([-55, -42, -30].enumerated()), id: \.offset) { i, threshold in
                RoundedRectangle(cornerRadius: 1)
                    .fill(level >= Float(threshold) ? Theme.ok : Color.white.opacity(0.18))
                    .frame(width: 3, height: CGFloat(6 + i * 3))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(level >= -55 ? "есть сигнал" : "тишина")")
    }
}

private struct StatusPill: View {
    let text: String
    let color: Color
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
}

private struct OverlayMenu: View {
    let model: PanelModel
    var body: some View {
        Menu {
            Toggle("Автоответ на вопросы", isOn: Binding(get: { model.autoGenerate }, set: { _ in model.onToggleAuto?() }))
            Picker("Язык звонка", selection: Binding(get: { model.language }, set: { model.onSelectLanguage?($0) })) {
                ForEach(RecognitionLanguage.allCases, id: \.self) { Text($0.menuTitle).tag($0) }
            }
            Divider()
            Button("Крупнее") { model.onZoom?(1) }
            Button("Мельче") { model.onZoom?(-1) }
            Button("Обычный размер (\(Int((model.zoom * 100).rounded()))%)") { model.onZoom?(0) }
            Button("На другой экран") { model.onNextScreen?() }
            Divider()
            Toggle("Скрывать при демонстрации экрана", isOn: Binding(get: { model.hiddenFromCapture }, set: { _ in model.onTogglePrivate?() }))
            Button(model.checkingVisibility ? "Проверяю видимость…" : "Проверить видимость") { model.onCheckVisibility?() }
                .disabled(model.checkingVisibility)
            if let result = model.visibilityResult { Text(result) }
            if model.sessionActive {
                Divider()
                Button("Завершить сессию", role: .destructive) { model.onEndSession?() }
            }
        } label: {
            Image(systemName: "ellipsis").frame(width: 22, height: 22).background(Circle().fill(Color.white.opacity(0.1)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Меню оверлея")
        .accessibilityLabel("Меню оверлея")
    }
}

// MARK: Без сессии

private struct NoSessionView: View {
    let model: PanelModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let app = model.callDetected {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Похоже, начался звонок: \(app)", systemImage: "phone.arrow.down.left")
                        .font(.system(size: model.fontSize, weight: .semibold))
                    Text("Начать сессию с последними настройками?").foregroundStyle(.white.opacity(0.75))
                    HStack {
                        Button("Начать") { model.onStartDetectedCall?() }.buttonStyle(.borderedProminent).tint(Theme.accent)
                        Button("Настроить…") { model.onCreateSession?() }
                        Button("Не сейчас") { model.onDismissDetectedCall?() }
                    }
                    .controlSize(.small)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color.white.opacity(0.08)))
            }
            Message(icon: "pause.circle", text: "Сессии нет — приложение не слушает звонок и микрофон.")
            Button("Создать сессию… \(model.hotkey(.newSession))") { model.onCreateSession?() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .accessibilityHint("Открывает мастер: тип звонка, профиль, проверка перед стартом")
        }
    }
}

// MARK: Расшифровка и статус вопроса

private struct TranscriptStrip: View {
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "waveform").foregroundStyle(model.partial != nil ? Theme.ok : .white.opacity(0.5))
                    .accessibilityHidden(true)
                Group {
                    if let partial = model.partial {
                        (Text(partial) + Text(" ▍").foregroundColor(.white.opacity(0.6)))
                    } else if let last = model.lines.last(where: { $0.filtered == nil }) {
                        Text(last.text)
                    } else {
                        Text(model.state == .paused ? "Пауза: ничего не слушаю и не отправляю." : "Жду, когда собеседник заговорит…")
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .lineLimit(model.transcriptExpanded ? nil : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Собеседник: \(model.partial ?? model.lines.last?.text ?? "тишина")")
                Button { model.onClearTranscript?() } label: {
                    Text("Очистить \(model.hotkey(.clearTranscript))").font(.system(size: max(9, model.fontSize - 4)))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("Очистить расшифровку и «последние реплики» для следующего ответа; память интервью остаётся")
                IconButton(symbol: model.transcriptExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                           label: model.transcriptExpanded ? "Свернуть расшифровку" : "Развернуть расшифровку") {
                    model.transcriptExpanded.toggle()
                }
            }
            if model.transcriptExpanded || model.lines.contains(where: { $0.filtered != nil && $0.id == model.lines.last?.id }) {
                ForEach(model.transcriptExpanded ? model.lines.dropLast() : [], id: \.id) { line in TranscriptLineView(model: model, line: line) }
                if let last = model.lines.last, last.filtered != nil { TranscriptLineView(model: model, line: last) }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color.white.opacity(0.06)))
    }
}

private struct TranscriptLineView: View {
    let model: PanelModel
    let line: PanelModel.Line
    var body: some View {
        if let reason = line.filtered {
            // COPILOT-05 R-06, S-08: отфильтрованное — серым; клик — ответить всё равно.
            Button { model.onAnswerFiltered?(line.text) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.text).italic().foregroundStyle(.white.opacity(0.5))
                    Text("игнорировано: \(reason) · нажмите или \(model.hotkey(.answerNow)), чтобы ответить")
                        .font(.system(size: model.fontSize - 4)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Игнорировано, \(reason): \(line.text). Ответить")
        } else {
            Text(line.text).foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DetectionChip: View {
    let model: PanelModel
    var body: some View {
        switch model.detection {
        case .idle:
            EmptyView()
        case .checking:
            chip("Проверяю…", color: Theme.warn, spinner: true)
        case .detected:
            chip("Вопрос найден", color: Theme.ok)
        case .notQuestion:
            chip("Не вопрос · ответить вручную \(model.hotkey(.answerNow))", color: .gray)
        }
    }

    private func chip(_ text: String, color: Color, spinner: Bool = false) -> some View {
        HStack(spacing: 6) {
            if spinner { ProgressView().controlSize(.mini) } else { Circle().fill(color).frame(width: 7, height: 7) }
            Text(text)
        }
        .font(.system(size: max(10, model.fontSize - 3), weight: .medium))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.18)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: Вспомогательное

private struct Banner: View {
    let icon: String
    let text: String
    let color: Color
    let size: Double
    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: size - 2, weight: .medium))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct Message: View {
    let icon: String
    let text: String
    var body: some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: icon) }
            .foregroundStyle(.white.opacity(0.85))
    }
}

private struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon.font(.system(size: 8, weight: .bold)) }
    }
}

// MARK: Чат (R-10)

private struct ChatField: View {
    @Bindable var model: PanelModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Режим", selection: $model.chatMode) {
                ForEach(PanelModel.ChatMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                        .disabled(mode == .refine && model.history.current == nil)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack {
                TextField(placeholder, text: $model.chatText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($focused)
                    .onSubmit(submit)
                Button(action: submit) { Image(systemName: "arrow.up.circle.fill").font(.title3) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .disabled(model.chatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Отправить")
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.1)))
            Text("↩ отправить · Esc закрыть").font(.system(size: max(9, model.fontSize - 4))).foregroundStyle(.white.opacity(0.5))
        }
        .onAppear { focused = true }
        .onExitCommand { model.onToggleChat?() }
    }

    private var placeholder: String {
        switch model.chatMode {
        case .question: "Вопрос текстом — ответ как на голосовой"
        case .refine: "Как поправить ответ: «короче», «без Kafka», «пример кода»"
        case .session: "Указание до конца сессии: «отвечай по-английски»"
        }
    }

    private func submit() {
        let text = model.chatText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.onChatSubmit?(text, model.chatMode)
        model.chatText = ""
    }
}
