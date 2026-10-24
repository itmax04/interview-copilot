import AppKit
import CopilotCore
import Observation
import SwiftUI

/// Разделы главного окна (P12).
enum WorkspaceSection: String, CaseIterable, Identifiable {
    case today = "Сегодня"
    case sessions = "Сессии"
    case profiles = "Профили"
    case mock = "ИИ-собеседование"
    case settings = "Настройки"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .today: "house"
        case .sessions: "clock"
        case .profiles: "doc.text"
        case .mock: "bolt"
        case .settings: "gearshape"
        }
    }
}

/// Состояние главного окна: раздел и то, что окно показывает о сессии (COPILOT-09 этап 6, P12). Логика сессии —
/// в `LiveSessionController`; окно только вызывает действия AppDelegate.
@MainActor
@Observable
final class WorkspaceModel {
    var section: WorkspaceSection = .today
    /// Сессия, которую открыть в «Сессиях» (после End — только что завершенная).
    var selectedSession: String?
    /// Растет, когда история сессий изменилась (End, удаление) — «Сегодня» перечитывает последние.
    var sessionsVersion = 0

    var sessionActive = false
    var sessionTimer: String?
    var sessionTitle: String?
    var recognitionStatus = ""
    var recognizerReady = false

    var onCreateSession: (() -> Void)?
    var onTestCall: (() -> Void)?
    var onMock: (() -> Void)?
    var onShowPanel: (() -> Void)?
    var onEndSession: (() -> Void)?
    var onOpenPermissions: (() -> Void)?
}

@MainActor
final class WorkspaceWindowController {
    private var window: NSWindow?
    let workspace: WorkspaceModel
    private let model: AppModel
    private let bank: BankController
    private let store: SessionStore
    private let reviews: ReviewController
    private let preparer: QuestionPreparer
    private let hotkeyFailures: () -> [HotkeyAction: String]
    private let stylePreviewContext: () -> StylePreview.Context?

    init(workspace: WorkspaceModel, model: AppModel, bank: BankController, store: SessionStore, reviews: ReviewController,
         hotkeyFailures: @escaping () -> [HotkeyAction: String], stylePreviewContext: @escaping () -> StylePreview.Context?) {
        self.workspace = workspace
        self.model = model
        self.bank = bank
        self.store = store
        self.reviews = reviews
        self.preparer = QuestionPreparer(bank: bank, model: model)
        self.hotkeyFailures = hotkeyFailures
        self.stylePreviewContext = stylePreviewContext
    }

    var isVisible: Bool { window?.isVisible == true }

    func show(_ section: WorkspaceSection? = nil, select session: String? = nil) {
        if let section { workspace.section = section }
        if let session { workspace.selectedSession = session }
        workspace.sessionsVersion += 1
        if window == nil {
            let root = WorkspaceView(workspace: workspace, model: model, bank: bank, store: store, reviews: reviews, preparer: preparer,
                                     hotkeyFailures: hotkeyFailures, stylePreviewContext: stylePreviewContext)
            let w = NSWindow(contentViewController: NSHostingController(rootView: root))
            w.title = "Interview Copilot"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.setContentSize(NSSize(width: 1180, height: 780))
            w.minSize = NSSize(width: 980, height: 640)
            // P00, P12: светлые окна, темный — только оверлей.
            w.appearance = NSAppearance(named: .aqua)
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("InterviewCopilotWorkspace")
            if w.frame.origin == .zero { w.center() }
            window = w
        }
        model.refreshKeys()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct WorkspaceView: View {
    @Bindable var workspace: WorkspaceModel
    @Bindable var model: AppModel
    let bank: BankController
    let store: SessionStore
    let reviews: ReviewController?
    let preparer: QuestionPreparer
    var hotkeyFailures: () -> [HotkeyAction: String] = { [:] }
    var stylePreviewContext: () -> StylePreview.Context? = { nil }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(IC.line).frame(width: 1)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .font(.system(size: 14))
        .foregroundStyle(IC.ink)
        .tint(IC.accent)
        .background(IC.background)
        .environment(\.colorScheme, .light)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                ICLogo(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Interview Copilot").font(.system(size: 14, weight: .semibold))
                    Text("Ваш AI-помощник\nна собеседованиях").font(.system(size: 10)).foregroundStyle(IC.secondary)
                }
            }
            .padding(.top, 34)
            .padding(.bottom, 6)
            VStack(spacing: 4) {
                ForEach(WorkspaceSection.allCases) { s in
                    ICSidebarRow(title: s.rawValue, icon: s.symbol, selected: workspace.section == s) { workspace.section = s }
                }
            }
            Spacer()
            if workspace.sessionActive {
                VStack(alignment: .leading, spacing: 8) {
                    Button { workspace.onShowPanel?() } label: { Label("Показать оверлей", systemImage: "rectangle.on.rectangle") }
                        .buttonStyle(ICButtonStyle())
                    Button { workspace.onEndSession?() } label: { Label("Завершить сессию", systemImage: "stop.circle") }
                        .buttonStyle(ICButtonStyle(destructive: true))
                }
            }
            HStack(spacing: 9) {
                Circle().fill(statusColor).frame(width: 9, height: 9)
                Text(statusText).font(.system(size: 12, weight: .medium)).lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(statusColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
        }
        .padding(16)
        .frame(width: 230)
        .background(IC.sidebar)
    }

    private var ready: Bool { model.hasKey.values.contains(true) && Permissions.screenCaptureGranted }
    private var statusText: String {
        if workspace.sessionActive { return "Сессия идет" + (workspace.sessionTimer.map { " · \($0)" } ?? "") }
        return ready ? "Готов к звонку" : "Нужна настройка"
    }
    private var statusColor: Color { workspace.sessionActive || ready ? IC.green : IC.amber }

    @ViewBuilder private var content: some View {
        switch workspace.section {
        case .today:
            TodayView(workspace: workspace, model: model, bank: bank, store: store)
        case .sessions:
            SessionHistoryView(store: store, reviews: reviews, initialSelection: workspace.selectedSession)
                .id("\(workspace.sessionsVersion)-\(workspace.selectedSession ?? "")")
        case .profiles:
            ProfileView(bank: bank, preparer: preparer).padding(.top, 28)
        case .mock:
            MockLandingView(workspace: workspace, bank: bank)
        case .settings:
            SettingsView(model: model, hotkeyFailures: hotkeyFailures, stylePreviewContext: stylePreviewContext).padding(.top, 28)
        }
    }
}

// MARK: Сегодня (P12)

struct TodayView: View {
    let workspace: WorkspaceModel
    let model: AppModel
    let bank: BankController
    let store: SessionStore
    @State private var recent: [SessionRecord] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                Text("Готовность к собеседованию").font(.system(size: 15, weight: .semibold))
                HStack(spacing: 12) {
                    let mic = Permissions.microphone == .granted
                    readiness("Микрофон", "mic", mic ? "Готов к использованию" : "Нужен доступ — нажмите", mic) {
                        if !mic { workspace.onOpenPermissions?() }
                    }
                    readiness("Распознавание", "waveform", recognition, workspace.recognizerReady) {}
                    let first = model.settings.chain.first { model.hasKey[$0] == true }
                    readiness("Модели", "cpu", first?.displayName ?? "Добавьте ключ в Настройках", first != nil) {
                        if first == nil { workspace.section = .settings }
                    }
                    readiness("Профиль", "person", profileDetail, !bank.profile.resume.isEmpty) { workspace.section = .profiles }
                }
                HStack(alignment: .top, spacing: 16) {
                    recentSessions.frame(maxWidth: .infinity)
                    preparation.frame(width: 300)
                }
                Label("Распознавание речи — на этом Mac. В модели уходит только текст вопроса и нужный контекст.",
                      systemImage: "lock.shield")
                    .font(.system(size: 11)).foregroundStyle(IC.secondary)
            }
            .padding(28)
            .padding(.top, 8)
        }
        .onAppear { recent = Array(store.list().prefix(4)) }
        .onChange(of: workspace.sessionsVersion) { recent = Array(store.list().prefix(4)) }
    }

    private var recognition: String {
        let s = workspace.recognitionStatus
        let name = s.hasPrefix("Распознавание: ") ? String(s.dropFirst("Распознавание: ".count)) : s
        return name.isEmpty ? (model.settings.recognitionBackend == .parakeet ? "Parakeet" : "Whisper") : name
    }

    private var profileDetail: String {
        bank.profile.resume.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "\(bank.profile.name) — добавьте резюме" : bank.profile.name
    }

    private var hero: some View {
        HStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 14) {
                Text(workspace.sessionActive ? "Сессия идет" : "Готов к собеседованию")
                    .font(.system(size: 34, weight: .bold))
                Text(workspace.sessionActive
                     ? "Подсказки — в оверлее рядом со звонком.\nЗавершите сессию, чтобы получить разбор."
                     : "AI будет слушать, анализировать вопросы\nи подсказывать ответы в реальном времени.")
                    .font(.system(size: 17)).foregroundStyle(IC.secondary).lineSpacing(3)
                HStack(spacing: 12) {
                    if workspace.sessionActive {
                        Button { workspace.onShowPanel?() } label: { Label("Показать оверлей", systemImage: "rectangle.on.rectangle") }
                            .buttonStyle(ICButtonStyle(primary: true))
                    } else {
                        Button { workspace.onCreateSession?() } label: {
                            HStack(spacing: 10) {
                                Label("Создать сессию", systemImage: "paperplane")
                                Text(model.settings.hotkey(.newSession).displayString).font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
                            }
                        }
                        .buttonStyle(ICButtonStyle(primary: true))
                        Button { workspace.onTestCall?() } label: { Label("Пробный звонок", systemImage: "play") }
                            .buttonStyle(ICButtonStyle())
                    }
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
            ZStack {
                ForEach(0..<3) { i in
                    RoundedRectangle(cornerRadius: 40).stroke(IC.accent.opacity(0.10), lineWidth: 1)
                        .frame(width: CGFloat(120 + i * 34), height: CGFloat(120 + i * 34)).rotationEffect(.degrees(-16))
                }
                ICLogo(size: 104).rotationEffect(.degrees(-10)).shadow(color: IC.accent.opacity(0.22), radius: 22, y: 12)
            }
            .frame(width: 220, height: 190)
            .accessibilityHidden(true)
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .leading)
        .background(LinearGradient(colors: [Color(hex: 0xDCE6FF), Color(hex: 0xF3F6FF)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20))
    }

    private func readiness(_ title: String, _ symbol: String, _ detail: String, _ ok: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 18)).foregroundStyle(ok ? IC.green : IC.amber)
                Image(systemName: symbol).font(.system(size: 20)).frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(detail).font(.system(size: 11)).foregroundStyle(IC.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(IC.line))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(detail)")
    }

    private var recentSessions: some View {
        ICCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Последние сессии").font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Button { workspace.selectedSession = nil; workspace.section = .sessions } label: {
                        HStack(spacing: 4) { Text("Все сессии"); Image(systemName: "chevron.right") }
                    }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(IC.secondary)
                }
                if recent.isEmpty {
                    ICEmptyState(icon: "clock", title: "Здесь появится история",
                                 detail: "После звонка вы сможете вернуться к вопросам, вашим ответам и разбору.")
                        .frame(height: 170)
                } else {
                    HStack {
                        Text("Дата и время").frame(width: 112, alignment: .leading)
                        Text("Компания").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Тип").frame(width: 116, alignment: .leading)
                        Text("Время").frame(width: 64, alignment: .leading)
                        Text("Разбор").frame(width: 80, alignment: .leading)
                    }
                    .font(.system(size: 11)).foregroundStyle(IC.secondary)
                    Divider()
                    ForEach(recent) { s in
                        Button { workspace.selectedSession = s.id; workspace.section = .sessions; workspace.sessionsVersion += 1 } label: {
                            row(s)
                        }
                        .buttonStyle(.plain)
                        if s.id != recent.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func row(_ s: SessionRecord) -> some View {
        let company = s.config?.company.isEmpty == false ? s.config!.company : (s.source ?? "Сессия")
        let role = s.config?.jobDescription.split(separator: "\n").first.map { String($0.prefix(40)) } ?? ""
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.startedAt.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "ru_RU")))).font(.system(size: 13))
                Text(s.startedAt.formatted(.dateTime.hour().minute().locale(Locale(identifier: "ru_RU")))).font(.system(size: 11)).foregroundStyle(IC.secondary)
            }
            .frame(width: 112, alignment: .leading)
            HStack(spacing: 10) {
                Text(String(company.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(avatarColor(company), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(company).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if !role.isEmpty { Text(role).font(.system(size: 11)).foregroundStyle(IC.secondary).lineLimit(1) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ICBadge(text: s.config?.type.title ?? "Сессия").frame(width: 116, alignment: .leading)
            Text(s.endedAt.map { "\(max(1, Int($0.timeIntervalSince(s.startedAt) / 60))) мин" } ?? "—")
                .font(.system(size: 13)).frame(width: 64, alignment: .leading)
            reviewBadge(s).frame(width: 80, alignment: .leading)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func reviewBadge(_ s: SessionRecord) -> some View {
        switch s.review?.status {
        case .done: ICBadge(text: "Готов", color: IC.green, dot: true)
        case .failed: ICBadge(text: "Прерван", color: IC.amber, dot: true)
        case .running, .pending: ICBadge(text: "Идет", color: IC.accent, dot: true)
        case .none: Text("—").foregroundStyle(IC.secondary)
        }
    }

    /// Цвет аватара по имени компании — стабильный, без логотипов чужих брендов.
    private func avatarColor(_ name: String) -> Color {
        let palette: [Color] = [IC.accent, Color(hex: 0x7048E8), Color(hex: 0x1098AD), Color(hex: 0xE8590C), Color(hex: 0x2B8A3E), Color(hex: 0xC2255C)]
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }

    private var preparation: some View {
        let cards = bank.cards
        let own = cards.filter { $0.status == .own || $0.status == .approved }.count
        let drafts = cards.filter { $0.status == .draft }.count
        let none = cards.filter { $0.status == .none }.count
        let phrased = cards.filter(\.prepared).count
        return ICCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Подготовка").font(.system(size: 16, weight: .semibold))
                HStack {
                    Text("Вопросы с ответом")
                    Spacer()
                    Text("\(own + drafts) / \(cards.count)").monospacedDigit()
                }
                .font(.system(size: 13))
                ProgressView(value: Double(own + drafts), total: Double(max(1, cards.count))).tint(IC.accent)
                prepRow("Ваши ответы", own, cards.count, IC.green)
                prepRow("Черновики — проверить", drafts, cards.count, IC.amber)
                prepRow("Без ответа", none, cards.count, Color(hex: 0xA1A1AA))
                prepRow("Формулировки uk / ru / en", phrased, cards.count, IC.accent)
                Button { workspace.section = .profiles } label: {
                    Label("Подготовить", systemImage: "doc.text").frame(maxWidth: .infinity)
                }
                .buttonStyle(ICButtonStyle(primary: true))
                .disabled(cards.isEmpty && bank.profile.resume.isEmpty)
            }
        }
    }

    private func prepRow(_ title: String, _ n: Int, _ total: Int, _ color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.system(size: 12)).foregroundStyle(Color(hex: 0x45516C))
            Spacer()
            Text("\(n) / \(total)").font(.system(size: 12)).foregroundStyle(IC.secondary).monospacedDigit()
        }
    }
}

// MARK: ИИ-собеседование (P19 — вход)

struct MockLandingView: View {
    let workspace: WorkspaceModel
    let bank: BankController

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ICPageHeader(title: "ИИ-собеседование", subtitle: "Репетиция: модель задает вопросы голосом, вы отвечаете в микрофон")
            HStack(alignment: .top, spacing: 20) {
                ICCard {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Перед началом").font(.system(size: 17, weight: .semibold))
                        Label(bank.profile.name, systemImage: "person.crop.circle")
                        Text("Вопросы — по резюме и вакансии профиля. Подсказки показываются в оверлее, как на настоящем звонке; после окончания — разбор.")
                            .font(.system(size: 13)).foregroundStyle(IC.secondary).fixedSize(horizontal: false, vertical: true)
                        Button { workspace.onMock?() } label: { Label("Начать собеседование", systemImage: "play.fill") }
                            .buttonStyle(ICButtonStyle(primary: true))
                            .disabled(workspace.sessionActive)
                        if workspace.sessionActive {
                            Text("Сначала завершите текущую сессию.").font(.system(size: 11)).foregroundStyle(IC.amber)
                        }
                    }
                }
                .frame(width: 320)
                ICCard {
                    VStack(spacing: 20) {
                        Image(systemName: "waveform").font(.system(size: 40)).foregroundStyle(IC.accent)
                            .frame(width: 110, height: 110).background(IC.accent.opacity(0.08), in: Circle())
                        Text("Один вопрос за раз").font(.system(size: 20, weight: .semibold))
                        Text("Интервьюер говорит голосом macOS в браузере. Отвечайте вслух — помощник покажет подсказку, а разбор подскажет, что улучшить.")
                            .font(.system(size: 13)).foregroundStyle(IC.secondary).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            }
            Spacer()
        }
        .padding(28)
        .padding(.top, 20)
    }
}
