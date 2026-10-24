import AppKit
import CopilotCore
import SwiftUI

/// Окно сессий — R-19, COPILOT-09 R-14: список, разбор («Сводка»), расшифровка по говорящим, «Спросить ИИ», удаление.
@MainActor
final class SessionHistoryWindowController {
    private var window: NSWindow?
    private let sessions: SessionController
    private let reviews: ReviewController?

    init(sessions: SessionController, reviews: ReviewController? = nil) {
        self.sessions = sessions
        self.reviews = reviews
    }

    /// `select` — открыть на этой сессии (после End — только что завершенная).
    func show(select: String? = nil) {
        sessions.saveNow()
        let view = SessionHistoryView(store: sessions.store, reviews: reviews, initialSelection: select)
        if let window {
            window.contentViewController = NSHostingController(rootView: view)
        } else {
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Сессии"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 980, height: 680))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SessionHistoryView: View {
    let store: SessionStore
    var reviews: ReviewController?
    var initialSelection: String?
    @State private var sessions: [SessionRecord] = []
    @State private var selection: String?
    @State private var confirmDeleteAll = false

    var body: some View {
        NavigationSplitView {
            List(sessions, selection: $selection) { s in
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.config?.company.isEmpty == false ? s.config!.company : s.startedAt.formatted(date: .abbreviated, time: .shortened))
                    Text(subtitle(s)).font(.caption).foregroundStyle(.secondary)
                }
                .tag(s.id)
                .contextMenu {
                    Button("Удалить", role: .destructive) { delete(s.id) }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .toolbar {
                ToolbarItem {
                    Button("Удалить всё", role: .destructive) { confirmDeleteAll = true }
                        .disabled(sessions.isEmpty)
                }
            }
        } detail: {
            if let id = selection, let s = sessions.first(where: { $0.id == id }) {
                SessionDetail(session: s, reviews: reviews) { delete(s.id) }
                    .id(s.id)
            } else {
                Text(sessions.isEmpty ? "История пуста" : "Выберите сессию").foregroundStyle(.secondary)
            }
        }
        .tint(Theme.accent)
        .onAppear {
            selection = initialSelection
            reload()
        }
        // Разбор идет в фоне — запись перечитывается при каждом шаге.
        .onChange(of: reviews?.version) { reload() }
        .confirmationDialog("Удалить всю историю сессий?", isPresented: $confirmDeleteAll) {
            Button("Удалить всё", role: .destructive) {
                try? store.deleteAll()
                reload()
            }
        }
    }

    private func subtitle(_ s: SessionRecord) -> String {
        var parts = [s.config?.type.title ?? (s.source ?? "—")]
        if s.config?.company.isEmpty == false { parts.append(s.startedAt.formatted(date: .abbreviated, time: .shortened)) }
        parts.append(RussianPlural.questions(max(s.exchanges.count, s.turns.count)))
        if case .done = s.review?.status { parts.append("разбор") }
        return parts.joined(separator: " · ")
    }

    private func reload() {
        sessions = store.list()
        if selection == nil || !sessions.contains(where: { $0.id == selection }) { selection = sessions.first?.id }
    }

    private func delete(_ id: String) {
        try? store.delete(id)
        if selection == id { selection = nil }
        reload()
    }
}

struct SessionDetail: View {
    enum Tab: String, CaseIterable {
        case summary = "Сводка"
        case transcript = "Расшифровка"
        case ask = "Спросить ИИ"
    }

    let session: SessionRecord
    var reviews: ReviewController?
    let onDelete: () -> Void
    @State private var tab: Tab

    init(session: SessionRecord, reviews: ReviewController?, tab: Tab = .summary, onDelete: @escaping () -> Void) {
        self.session = session
        self.reviews = reviews
        self.onDelete = onDelete
        _tab = State(initialValue: tab)
    }
    @State private var showHints = true
    @State private var question = ""
    @State private var confirmDelete = false

    private var isRegular: Bool { session.config?.type == .regular }
    private var asker: String { isRegular ? "Собеседник" : "Интервьюер" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            reviewStatus
            Picker("Раздел", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch tab {
            case .summary: summaryTab
            case .transcript: transcriptTab
            case .ask: askTab
            }
        }
        .padding(20)
        .confirmationDialog("Удалить сессию вместе с разбором?", isPresented: $confirmDelete) {
            Button("Удалить", role: .destructive, action: onDelete)
        }
    }

    // MARK: Шапка и статус разбора

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.bold())
                Text(details).foregroundStyle(.secondary).font(.callout)
            }
            Spacer()
            Button("Удалить сессию", role: .destructive) { confirmDelete = true }
        }
    }

    private var title: String {
        let date = session.startedAt.formatted(date: .long, time: .shortened)
        guard let c = session.config, !c.company.isEmpty else { return date }
        return "\(c.company) — \(date)"
    }

    private var details: String {
        var parts: [String] = []
        if let c = session.config { parts.append(c.type.title) }
        if let end = session.endedAt { parts.append("\(max(1, Int(end.timeIntervalSince(session.startedAt) / 60))) мин") }
        if let src = session.source { parts.append(src) }
        parts.append(RussianPlural.questions(max(session.exchanges.count, session.turns.count)))
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var reviewStatus: some View {
        let running = reviews?.running.contains(session.id) == true
        switch session.review?.status {
        case .running(let done, let total) where running:
            statusRow(icon: nil, text: total > 0 && done < total ? "Разбор: \(done) из \(total) ответов…" : "Разбор: сводка…", color: .secondary)
        case .pending where running, .none where running:
            statusRow(icon: nil, text: "Разбор начинается…", color: .secondary)
        case .failed(let reason):
            HStack {
                statusRow(icon: "exclamationmark.triangle.fill", text: "Разбор не закончен: \(reason). Готовые комментарии и расшифровка сохранены.", color: Theme.warn)
                Spacer()
                Button("Повторить") { reviews?.start(session.id) }.disabled(reviews == nil || running)
            }
        case .done:
            EmptyView()
        default:
            if session.canBeReviewed, reviews != nil {
                HStack {
                    statusRow(icon: "sparkles", text: session.review == nil ? "Разбора нет" : "Разбор прерван", color: .secondary)
                    Spacer()
                    Button(session.review == nil ? "Сделать разбор" : "Продолжить разбор") { reviews?.start(session.id) }
                        .disabled(running)
                }
            }
        }
    }

    private func statusRow(icon: String?, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            if let icon { Image(systemName: icon).foregroundStyle(color) } else { ProgressView().controlSize(.small) }
            Text(text).foregroundStyle(color).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Сводка: общая сводка, затем вопрос → ваш ответ → комментарий → подсказка

    private var summaryTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let s = session.review?.summary { summaryCard(s) }
                if session.exchanges.isEmpty {
                    // Сессии до COPILOT-06: только вопросы и подсказки.
                    ForEach(Array(session.turns.enumerated()), id: \.offset) { _, t in
                        card {
                            Text(t.question).font(.headline)
                            Text(t.answer.isEmpty ? "Нет в базе" : t.answer).textSelection(.enabled)
                            Text(meta(t)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(session.exchanges) { e in exchangeCard(e) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summaryCard(_ s: ReviewSummary) -> some View {
        card {
            Text("Сводка").font(.headline)
            if !s.overview.isEmpty { Text(s.overview).textSelection(.enabled) }
            list("Темы", s.topics, icon: "text.bubble")
            list("Получилось", s.strengths, icon: "checkmark.circle", color: Theme.ok)
            list("Что улучшить", s.weaknesses, icon: "arrow.up.circle", color: Theme.warn)
            list("Договоренности", s.agreements, icon: "handshake")
            list("Следующие шаги", s.nextSteps, icon: "arrow.right.circle", color: Theme.accent)
        }
    }

    @ViewBuilder private func list(_ title: String, _ items: [String], icon: String, color: Color = .secondary) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).padding(.top, 4)
                ForEach(items, id: \.self) { item in
                    Label { Text(item).textSelection(.enabled) } icon: { Image(systemName: icon).foregroundStyle(color) }
                }
            }
        }
    }

    private func exchangeCard(_ e: SessionExchange) -> some View {
        card {
            Text(e.question).font(.headline).textSelection(.enabled)
            if e.answerText.isEmpty {
                Text("Ваш ответ не записан").foregroundStyle(.secondary).font(.callout)
            } else {
                Text("Вы: \(e.answerText)").textSelection(.enabled)
            }
            if let c = session.review?.comment(for: e.id) {
                VStack(alignment: .leading, spacing: 4) {
                    if !c.good.isEmpty { Label(c.good, systemImage: "checkmark.circle").foregroundStyle(Theme.ok) }
                    if !c.missing.isEmpty { Label(c.missing, systemImage: "exclamationmark.circle").foregroundStyle(Theme.warn) }
                    if !c.better.isEmpty {
                        (Text("Лучше: ").fontWeight(.semibold) + Text(c.better)).textSelection(.enabled)
                    }
                }
                .font(.callout)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.08)))
            }
            if let hint = e.hint, !hint.isEmpty {
                DisclosureGroup("Подсказка на экране") {
                    MarkdownText(hint, fontSize: 12).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
            }
        }
    }

    // MARK: Расшифровка по говорящим

    private var transcriptTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Показывать подсказки", isOn: $showHints).toggleStyle(.checkbox)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    let lines = session.timeline.filter { showHints || $0.speaker != .hint }
                    if lines.isEmpty { Text("Расшифровки нет").foregroundStyle(.secondary) }
                    ForEach(lines) { line in
                        HStack(alignment: .top, spacing: 10) {
                            Text(line.clock).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(label(line.speaker)).font(.caption.weight(.semibold)).foregroundStyle(color(line.speaker))
                                if line.speaker == .hint {
                                    MarkdownText(line.text, fontSize: 12).foregroundStyle(.secondary)
                                } else {
                                    Text(line.text).textSelection(.enabled)
                                }
                            }
                            .padding(line.speaker == .hint ? 8 : 0)
                            .background(RoundedRectangle(cornerRadius: 6).fill(line.speaker == .hint ? Color.secondary.opacity(0.08) : .clear))
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func label(_ s: TimelineEntry.Speaker) -> String {
        switch s {
        case .interviewer: asker
        case .owner: "Вы"
        case .hint: "Подсказка"
        }
    }

    private func color(_ s: TimelineEntry.Speaker) -> Color {
        switch s {
        case .interviewer: Theme.accent
        case .owner: Theme.ok
        case .hint: .secondary
        }
    }

    // MARK: Спросить ИИ

    private var askTab: some View {
        let busy = reviews?.asking.contains(session.id) == true
        return VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    let chat = session.review?.chat ?? []
                    if chat.isEmpty && !busy {
                        Text("Спросите о звонке — модель ответит по расшифровке.").foregroundStyle(.secondary)
                        HStack {
                            ForEach(suggestions, id: \.self) { s in
                                Button(s) { send(s) }.buttonStyle(.bordered).controlSize(.small).disabled(reviews == nil)
                            }
                        }
                    }
                    ForEach(chat) { qa in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(qa.question).fontWeight(.semibold)
                            MarkdownText(qa.answer, fontSize: 13).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
                    }
                    if busy { HStack { ProgressView().controlSize(.small); Text("Думаю…").foregroundStyle(.secondary) } }
                    if let error = reviews?.askError[session.id] {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                TextField("Например: где я отвечал слабее всего?", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { send(question) }
                Button("Спросить") { send(question) }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || reviews == nil || question.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var suggestions: [String] {
        isRegular
            ? ["О чем договорились?", "Что мне сделать дальше?"]
            : ["Где я отвечал слабее всего?", "Что подготовить к следующему этапу?"]
    }

    private func send(_ text: String) {
        guard let reviews, !(reviews.asking.contains(session.id)) else { return }
        reviews.ask(session.id, question: text)
        question = ""
    }

    // MARK: Общее

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.07)))
    }

    private func meta(_ t: SessionRecord.TurnRecord) -> String {
        var parts = [t.source == "bank" ? "Bank" + (t.cardID.map { " · \($0)" } ?? "") : (t.model ?? t.source)]
        if let ms = t.cardShownMs { parts.append(String(format: "%.1f с", ms / 1000)) }
        if let ms = t.firstTokenMs { parts.append(String(format: "первые слова %.1f с", ms / 1000)) }
        if let i = t.inputTokens, let o = t.outputTokens { parts.append("токены \(i)/\(o)") }
        if t.forced { parts.append("вручную") }
        return parts.joined(separator: " · ")
    }
}

/// Склонение числительных для подписей (1 вопрос, 2 вопроса, 5 вопросов).
enum RussianPlural {
    static func form(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n10 = n % 10, n100 = n % 100
        if n10 == 1 && n100 != 11 { return one }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return few }
        return many
    }

    static func questions(_ n: Int) -> String { "\(n) \(form(n, "вопрос", "вопроса", "вопросов"))" }
}
