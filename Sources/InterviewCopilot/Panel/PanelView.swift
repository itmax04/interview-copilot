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
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .foregroundStyle(.white)
        .font(.system(size: model.fontSize))
        .frame(minWidth: 300, maxWidth: .infinity, minHeight: model.collapsed ? 0 : 220, maxHeight: .infinity, alignment: .topLeading)
        // P00: темное стекло #16181D 82% поверх размытия окна.
        .background(ICDark.glass)
        .overlay {
            // Проверка видимости (R-17): контрольный цвет на долю секунды — по нему видно, попал ли оверлей в захват экрана.
            if model.visibilityProbe { Color(red: 1, green: 0, blue: 1) }
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var notes: some View {
        if !model.sessionNotes.isEmpty {
            VStack(spacing: 6) {
                ForEach(Array(model.sessionNotes.enumerated()), id: \.offset) { i, note in
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill").foregroundStyle(IC.accent)
                        Text("На всю сессию: \(note)").lineLimit(1)
                        Spacer(minLength: 4)
                        Button { model.onRemoveSessionNote?(i) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                            .buttonStyle(.plain)
                            .help("Снять указание")
                            .accessibilityLabel("Снять указание: \(note)")
                    }
                    .font(.system(size: model.fontSize - 2, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(IC.accent.opacity(0.22), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(IC.accent.opacity(0.45)))
                }
            }
        }
    }

    @ViewBuilder private var banners: some View {
        if let notice = model.planNotice {
            Banner(icon: "clock.badge.exclamationmark", text: notice, color: Theme.warn, size: model.fontSize)
        }
        if let silent = model.callSilentSeconds, silent >= 10 {
            AlertBox(icon: "speaker.slash.fill", text: "Не слышу звонок \(silent) с — проверьте звук вкладки или источник", size: model.fontSize)
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

/// Активная задача со скриншота (COPILOT-09 R-15, P05): миниатюры, «+ Добавить снимок», условие, ✕ — закрыть задачу.
private struct TaskChip: View {
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Активная задача · \(model.taskImages.count) \(model.taskImages.count == 1 ? "снимок" : "снимка")")
                    .font(.system(size: max(10, model.fontSize - 3))).foregroundStyle(ICDark.secondary)
                Spacer()
                Button { model.onCloseTask?() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.7))
                    .help("Закрыть задачу: вопросы больше не относятся к ней")
                    .accessibilityLabel("Закрыть задачу")
            }
            HStack(spacing: 8) {
                ForEach(Array(model.taskImages.enumerated()), id: \.offset) { _, data in
                    if let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 76, height: 46).clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(ICDark.stroke))
                            .accessibilityLabel("Снимок задачи")
                    }
                }
                if model.taskImages.count < 3 {
                    Button { model.onScreenshot?() } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "plus")
                            Text("Добавить снимок").font(.system(size: 9))
                            Text(model.hotkey(.screenshot)).font(.system(size: 9)).foregroundStyle(ICDark.secondary)
                        }
                        .frame(width: 92, height: 46)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ICDark.stroke, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    }
                    .buttonStyle(.plain)
                    .help("Снимок в течение 30 с — к этой же задаче")
                }
                Spacer(minLength: 0)
            }
            if let title = model.taskTitle {
                Text(title).font(.system(size: model.fontSize, weight: .semibold)).lineLimit(2)
            } else {
                Text(model.taskSolved ? "Уточнения голосом — к этой задаче" : "Решаю…").font(.system(size: model.fontSize - 2))
                    .foregroundStyle(ICDark.secondary)
            }
        }
        .padding(12)
        .background(ICDark.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ICDark.stroke))
        .accessibilityElement(children: .contain)
    }
}

private struct Toolbar: View {
    let model: PanelModel

    /// P01: сверху — уровни микрофона и звонка, таймер, свернуть, меню, «Завершить»; ниже — действия с клавишами.
    /// P06: свернутый — одна строка: волны, действия иконками, таймер, развернуть, «Завершить».
    @ViewBuilder var body: some View {
        if model.collapsed && model.sessionActive { collapsedRow } else { fullBody }
    }

    private var collapsedRow: some View {
        HStack(spacing: 7) {
            LevelWave(level: model.micLevel, icon: "mic.fill", label: "Микрофон", silent: false)
            LevelWave(level: model.callLevel, icon: "speaker.wave.2.fill", label: "Звук звонка", silent: model.callSilentSeconds != nil)
            Spacer(minLength: 2)
            ForEach([("doc", "Ответ", HotkeyAction.answerNow), ("crop", "Скриншот", .screenshot), ("bubble.left", "Чат", .chat)], id: \.1) { icon, title, action in
                IconButton(symbol: icon, label: "\(title) \(model.hotkey(action))") {
                    switch action {
                    case .answerNow: model.onAnswerNow?()
                    case .screenshot: model.onScreenshot?()
                    default: model.onToggleChat?()
                    }
                }
            }
            if let timer = model.sessionTimer {
                Text(timer).font(.system(size: model.fontSize - 2, weight: .medium).monospacedDigit()).lineLimit(1).fixedSize()
            }
            IconButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Развернуть") { model.onToggleCollapse?() }
            Button { model.onEndSession?() } label: {
                Circle().fill(.white).frame(width: 9, height: 9).frame(width: 30, height: 26)
                    .background(IC.red, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help("Завершить сессию")
            .accessibilityLabel("Завершить сессию")
        }
    }

    private var fullBody: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                if model.sessionActive {
                    LevelWave(level: model.micLevel, icon: "mic.fill", label: "Микрофон", silent: false)
                    Rectangle().fill(ICDark.divider).frame(width: 1, height: 20)
                    LevelWave(level: model.callLevel, icon: "speaker.wave.2.fill", label: "Звук звонка", silent: model.callSilentSeconds != nil)
                } else {
                    ICLogo(size: 22)
                    ICStatusPill(text: statusText, color: statusColor, size: max(10, model.fontSize - 3))
                }
                Spacer(minLength: 4)
                if model.sessionActive, let timer = model.sessionTimer {
                    Text(timer)
                        .font(.system(size: model.fontSize - 1, weight: .medium).monospacedDigit())
                        .lineLimit(1).fixedSize()
                        .foregroundStyle(.white.opacity(0.85))
                        .accessibilityLabel("Время сессии \(timer)")
                }
                IconButton(symbol: model.collapsed ? "chevron.down" : "minus", label: model.collapsed ? "Развернуть" : "Свернуть") {
                    model.onToggleCollapse?()
                }
                OverlayMenu(model: model)
                if model.sessionActive {
                    Button { model.onEndSession?() } label: {
                        HStack(spacing: 6) {
                            Circle().fill(.white).frame(width: 9, height: 9)
                            Text("Завершить").font(.system(size: model.fontSize - 2, weight: .semibold))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(IC.red, in: RoundedRectangle(cornerRadius: 9))
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Завершить сессию")
                    .accessibilityHint("Приложение перестанет слушать")
                }
            }
            if model.sessionActive && !model.collapsed {
                HStack(spacing: 6) {
                    ICOverlayButton(title: "Ответ", icon: "doc", keys: model.hotkey(.answerNow), size: model.fontSize) { model.onAnswerNow?() }
                        .help("Ответить на последнюю реплику сейчас")
                    ICOverlayButton(title: "Скриншот", icon: "crop", keys: model.hotkey(.screenshot), size: model.fontSize) { model.onScreenshot?() }
                        .help("Снимок экрана с задачей → решение")
                    ICOverlayButton(title: "Чат", icon: "bubble.left", keys: model.hotkey(.chat), size: model.fontSize) { model.onToggleChat?() }
                        .help("Вопрос текстом или уточнение ответа")
                    if model.selfTest {
                        ICOverlayButton(title: model.ownerAnswering ? "Конец" : "Я отвечаю", icon: "person.wave.2",
                                        keys: model.hotkey(.ownerAnswer), size: model.fontSize) { model.onOwnerAnswer?() }
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
        case .listening: IC.green
        case .noPermission, .error: IC.red
        case .paused, .downloading: IC.amber
        default: Color(hex: 0xA1A1AA)
        }
    }
}

private struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 26, height: 26)
                .background(ICDark.raised, in: Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// P01: иконка и «волна» из 9 полос; горит столько, сколько громкость (−60…−20 дБ). Звонок не слышен — красным (P02 №5).
private struct LevelWave: View {
    let level: Float
    let icon: String
    let label: String
    let silent: Bool
    private static let heights: [CGFloat] = [6, 11, 16, 20, 14, 18, 10, 13, 7]

    var body: some View {
        let lit = Int(((min(max(level, -60), -20) + 60) / 40 * Float(Self.heights.count)).rounded())
        HStack(spacing: 5) {
            Image(systemName: silent ? "mic.slash.fill" : icon).font(.system(size: 13))
                .foregroundStyle(silent ? IC.red : lit > 0 ? IC.green : .white.opacity(0.55))
            HStack(spacing: 2) {
                ForEach(Array(Self.heights.enumerated()), id: \.offset) { i, h in
                    Capsule()
                        .fill(silent ? IC.red.opacity(0.5) : i < lit ? IC.green : Color.white.opacity(0.18))
                        .frame(width: 2.5, height: silent ? 2.5 : h)
                }
            }
            .frame(height: 20)
        }
        .animation(.easeOut(duration: 0.12), value: lit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(silent ? "нет сигнала" : lit > 0 ? "есть сигнал" : "тишина")")
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
            Image(systemName: "ellipsis").rotationEffect(.degrees(90)).font(.system(size: 12, weight: .bold)).frame(width: 26, height: 26)
                .background(ICDark.raised, in: Circle())
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
                // P10: как уведомление — значок, «Звонок в Zoom», вопрос и две кнопки.
                HStack(alignment: .top, spacing: 12) {
                    ICLogo(size: 38)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Звонок в \(app)").font(.system(size: model.fontSize, weight: .semibold))
                        Text("Начать сессию с последними настройками?").font(.system(size: model.fontSize - 2)).foregroundStyle(ICDark.secondary)
                        HStack(spacing: 6) {
                            Button { model.onStartDetectedCall?() } label: {
                                Text("Начать").font(.system(size: model.fontSize - 2, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 6)
                                    .background(IC.accent, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            ICOverlayButton(title: "Настроить…", icon: "slider.horizontal.3", size: model.fontSize) { model.onCreateSession?() }
                        }
                        Button("Не сейчас") { model.onDismissDetectedCall?() }.buttonStyle(.plain)
                            .font(.system(size: model.fontSize - 3)).foregroundStyle(ICDark.secondary)
                    }
                }
                .padding(12)
                .background(ICDark.raised, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ICDark.stroke))
            }
            Message(icon: "pause.circle", text: "Сессии нет — приложение не слушает звонок и микрофон.")
            Button { model.onCreateSession?() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane")
                    Text("Создать сессию").font(.system(size: model.fontSize - 1, weight: .semibold))
                    ICKeycap(text: model.hotkey(.newSession), dark: true)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(IC.accent, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
                .accessibilityHint("Открывает мастер: тип звонка, профиль, проверка перед стартом")
        }
    }
}

// MARK: Расшифровка и статус вопроса

private struct TranscriptStrip: View {
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Собеседник").font(.system(size: max(9, model.fontSize - 4))).foregroundStyle(ICDark.secondary)
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
                }
                Button { model.onClearTranscript?() } label: {
                    HStack(spacing: 5) {
                        Text("Очистить").font(.system(size: max(10, model.fontSize - 3)))
                        ICKeycap(text: model.hotkey(.clearTranscript), dark: true)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(ICDark.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ICDark.stroke))
                    .fixedSize()
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
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(ICDark.divider).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(ICDark.divider).frame(height: 1) }
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
        // P02: «Готовлю ответ…» — пока у нового вопроса нет текста; иначе — статус распознавания (AC-04).
        let waiting: Bool = {
            if case .waiting? = model.history.current?.current?.status, model.history.isViewingLatest { return true }
            return false
        }()
        switch model.detection.display(answerWaiting: waiting) {
        case .hidden: EmptyView()
        case .preparing: ICStatusPill(text: "Готовлю ответ…", color: IC.accent, spinner: true, size: size)
        case .checking: ICStatusPill(text: "Проверяю…", color: IC.amber, size: size)
        case .detected: ICStatusPill(text: "Вопрос найден", color: IC.green, size: size)
        case .notQuestion: ICStatusPill(text: "Не вопрос · ответить вручную \(model.hotkey(.answerNow))", color: Color(hex: 0xA1A1AA), size: size)
        }
    }

    private var size: Double { max(10, model.fontSize - 2) }
}

// MARK: Вспомогательное

/// P02 №5–6: красная плашка с причиной.
struct AlertBox: View {
    let icon: String
    let text: String
    let size: Double
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(IC.red)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: size - 2, weight: .medium))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IC.red.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(IC.red.opacity(0.45)))
        .accessibilityElement(children: .combine)
    }
}

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
            HStack(spacing: 8) {
                Image(systemName: "text.bubble").foregroundStyle(ICDark.secondary)
                TextField(placeholder, text: $model.chatText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($focused)
                    .onSubmit(submit)
                Button(action: submit) {
                    Image(systemName: "paperplane.fill").font(.system(size: 13)).frame(width: 34, height: 30)
                        .background(IC.accent, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(model.chatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Отправить")
            }
            .padding(.leading, 10).padding(.trailing, 5).padding(.vertical, 5)
            .background(ICDark.surface, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(IC.accent, lineWidth: 1.5))
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
