import AppKit
import CopilotCore
import SwiftUI

/// Отдельное окно сессий (R-19). С COPILOT-09 этап 6 сессии живут в главном окне; окно оставлено для совместимости.
@MainActor
final class SessionHistoryWindowController {
    private var window: NSWindow?
    private let sessions: SessionController
    private let reviews: ReviewController?

    init(sessions: SessionController, reviews: ReviewController? = nil) {
        self.sessions = sessions
        self.reviews = reviews
    }

    func show(select: String? = nil) {
        sessions.saveNow()
        let view = SessionHistoryView(store: sessions.store, reviews: reviews, initialSelection: select)
        if let window {
            window.contentViewController = NSHostingController(rootView: view)
        } else {
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Сессии"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 980, height: 720))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private let ru = Locale(identifier: "ru_RU")

/// «Сессии» (P15): список сессий → страница сессии с разбором. Разбор идет в фоне — запись перечитывается на каждом шаге.
struct SessionHistoryView: View {
    let store: SessionStore
    var reviews: ReviewController?
    var initialSelection: String?
    /// Выбор сессии (и «К списку» — nil) — главное окно помнит его между разделами.
    var onSelect: ((String?) -> Void)?
    @State private var sessions: [SessionRecord] = []
    @State private var selection: String?
    @State private var search = ""
    @State private var confirmDeleteAll = false

    var body: some View {
        Group {
            if let id = selection, let s = sessions.first(where: { $0.id == id }) {
                SessionDetail(session: s, reviews: reviews, onBack: { selection = nil }) { delete(s.id) }
                    .id(s.id)
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(IC.background)
        .foregroundStyle(IC.ink)
        .tint(IC.accent)
                .onAppear {
            sessions = store.list()
            if let initialSelection, sessions.contains(where: { $0.id == initialSelection }) { selection = initialSelection }
        }
        .onChange(of: reviews?.version) { sessions = store.list() }
        .onChange(of: selection) { _, new in onSelect?(new) }
        .confirmationDialog("Удалить всю историю сессий вместе с разбором?", isPresented: $confirmDeleteAll) {
            Button("Удалить всё", role: .destructive) {
                try? store.deleteAll()
                sessions = store.list()
            }
        }
    }

    private var filtered: [SessionRecord] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return sessions }
        return sessions.filter { s in
            [s.config?.company ?? "", s.source ?? "", s.config?.jobDescription ?? ""].joined(separator: " ").lowercased().contains(q)
                || s.exchanges.contains { $0.question.lowercased().contains(q) }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                ICPageHeader(title: "Сессии", subtitle: "Звонки, ваши ответы, подсказки и разбор. История хранится только на этом Mac.")
                Button("Удалить всё", role: .destructive) { confirmDeleteAll = true }
                    .buttonStyle(ICButtonStyle())
                    .disabled(sessions.isEmpty)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(IC.secondary)
                TextField("Найти по компании или вопросу…", text: $search).textFieldStyle(.plain)
            }
            .padding(10)
            .background(IC.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(IC.line))
            if sessions.isEmpty {
                ICEmptyState(icon: "clock", title: "Сессий пока нет",
                             detail: "Создайте сессию перед звонком — после «Завершить» здесь появятся расшифровка и разбор.")
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(filtered) { s in
                            Button { selection = s.id } label: { SessionRow(session: s) }
                                .buttonStyle(.plain)
                                .contextMenu { Button("Удалить", role: .destructive) { delete(s.id) } }
                        }
                    }
                }
            }
        }
        .padding(28)
    }

    private func delete(_ id: String) {
        try? store.delete(id)
        if selection == id { selection = nil }
        sessions = store.list()
    }
}

private struct SessionRow: View {
    let session: SessionRecord
    var body: some View {
        HStack(spacing: 14) {
            CompanyAvatar(name: company, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(company).font(.system(size: 14, weight: .semibold))
                Text(details).font(.system(size: 12)).foregroundStyle(IC.secondary).lineLimit(1)
            }
            Spacer()
            ICBadge(text: session.config?.type.title ?? "Сессия")
            ReviewStatusBadge(session: session)
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(IC.secondary)
        }
        .padding(14)
        .background(IC.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(IC.line))
        .contentShape(Rectangle())
    }

    private var company: String { session.config?.company.isEmpty == false ? session.config!.company : (session.source ?? "Сессия") }
    private var details: String {
        var parts = [session.startedAt.formatted(.dateTime.day().month(.wide).hour().minute().locale(ru))]
        if let end = session.endedAt { parts.append("\(max(1, Int(end.timeIntervalSince(session.startedAt) / 60))) мин") }
        parts.append(RussianPlural.questions(max(session.exchanges.count, session.turns.count)))
        return parts.joined(separator: " · ")
    }
}

/// Буква компании на цветном квадрате — стабильный цвет по имени, без чужих логотипов.
struct CompanyAvatar: View {
    let name: String
    var size: CGFloat = 32
    var body: some View {
        let palette: [Color] = [IC.accent, Color(hex: 0x7048E8), Color(hex: 0x1098AD), Color(hex: 0xE8590C), Color(hex: 0x2B8A3E), Color(hex: 0xC2255C)]
        let color = palette[name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % palette.count]
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.44, weight: .bold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size * 0.26))
            .accessibilityHidden(true)
    }
}

struct ReviewStatusBadge: View {
    let session: SessionRecord
    var body: some View {
        switch session.review?.status {
        case .done: ICBadge(text: "Разбор готов", color: IC.green, dot: true)
        case .failed: ICBadge(text: "Разбор прерван", color: IC.amber, dot: true)
        case .running, .pending: ICBadge(text: "Разбор идет", color: IC.accent, dot: true)
        case .none: EmptyView()
        }
    }
}

// MARK: Страница сессии (P15, P16)

struct SessionDetail: View {
    enum Tab: String, CaseIterable {
        case summary = "Сводка"
        case transcript = "Расшифровка"
        case ask = "Спросить ИИ"
        var symbol: String {
            switch self {
            case .summary: "doc.text"
            case .transcript: "text.alignleft"
            case .ask: "sparkles"
            }
        }
    }

    let session: SessionRecord
    var reviews: ReviewController?
    var onBack: (() -> Void)?
    let onDelete: () -> Void
    @State private var tab: Tab
    @State private var showHints = true
    @State private var speaker: TimelineEntry.Speaker?
    @State private var search = ""
    @State private var question = ""
    @State private var confirmDelete = false

    init(session: SessionRecord, reviews: ReviewController?, tab: Tab = .summary, onBack: (() -> Void)? = nil,
         onDelete: @escaping () -> Void) {
        self.session = session
        self.reviews = reviews
        self.onBack = onBack
        self.onDelete = onDelete
        _tab = State(initialValue: tab)
    }

    private var isRegular: Bool { session.config?.type == .regular }
    private var asker: String { isRegular ? "Собеседник" : "Интервьюер" }
    private var running: Bool { reviews?.running.contains(session.id) == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            tabs
            switch tab {
            case .summary: summaryTab
            case .transcript: transcriptTab
            case .ask: askTab
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(IC.background)
        .foregroundStyle(IC.ink)
                .confirmationDialog("Удалить сессию вместе с разбором?", isPresented: $confirmDelete) {
            Button("Удалить", role: .destructive, action: onDelete)
        }
    }

    // MARK: Шапка

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                if let onBack {
                    Button(action: onBack) { Label("К списку сессий", systemImage: "arrow.left") }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(IC.secondary)
                }
                Text(title).font(.system(size: 30, weight: .bold)).lineLimit(1)
                HStack(spacing: 10) {
                    Text(details).font(.system(size: 14)).foregroundStyle(IC.secondary)
                    ICBadge(text: session.config?.type.title ?? "Сессия")
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                Button { confirmDelete = true } label: { Image(systemName: "trash").frame(width: 20, height: 20) }
                    .buttonStyle(ICButtonStyle())
                    .help("Удалить сессию")
                    .accessibilityLabel("Удалить сессию")
                reviewProgress
            }
        }
    }

    private var title: String {
        if let c = session.config, !c.company.isEmpty { return c.company }
        return session.source ?? "Сессия"
    }

    private var details: String {
        var parts = [session.startedAt.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(ru))]
        if let end = session.endedAt { parts.append("\(max(1, Int(end.timeIntervalSince(session.startedAt) / 60))) мин") }
        return parts.joined(separator: " · ")
    }

    /// P15: «Разбор готов» с полосой; в работе — «N из M», ошибка — причина и «Повторить».
    @ViewBuilder private var reviewProgress: some View {
        switch session.review?.status {
        case .done:
            progress(text: "Разбор готов", value: 1, color: IC.green, icon: "checkmark.circle.fill")
        case .running(let done, let total) where running:
            progress(text: total > 0 && done < total ? "Разбор: \(done) из \(total) ответов" : "Разбор: сводка…",
                     value: total > 0 ? Double(done) / Double(total + 1) : 0.5, color: IC.accent, icon: nil)
        case .pending where running, .none where running:
            progress(text: "Разбор начинается…", value: 0.05, color: IC.accent, icon: nil)
        case .failed(let reason):
            VStack(alignment: .trailing, spacing: 6) {
                Label("Разбор не закончен", systemImage: "exclamationmark.triangle.fill").foregroundStyle(IC.amber)
                    .font(.system(size: 12, weight: .medium))
                Text(reason).font(.system(size: 11)).foregroundStyle(IC.secondary).lineLimit(2).frame(maxWidth: 300, alignment: .trailing)
                Button("Повторить") { reviews?.start(session.id) }.buttonStyle(ICButtonStyle(primary: true)).disabled(reviews == nil || running)
            }
        default:
            if session.canBeReviewed, reviews != nil {
                Button(session.review == nil ? "Сделать разбор" : "Продолжить разбор") { reviews?.start(session.id) }
                    .buttonStyle(ICButtonStyle(primary: true)).disabled(running)
            }
        }
    }

    private func progress(text: String, value: Double, color: Color, icon: String?) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).foregroundStyle(color) } else { ProgressView().controlSize(.small) }
                Text(text).font(.system(size: 12, weight: .medium))
            }
            ProgressView(value: value).tint(color).frame(width: 260)
        }
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { t in
                let selected = t == tab
                Button { tab = t } label: {
                    Label(t.rawValue, systemImage: t.symbol)
                        .font(.system(size: 14, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? IC.accent : IC.ink2)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(selected ? IC.card : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? IC.accent.opacity(0.5) : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(IC.muted, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Сводка

    private var summaryTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let s = session.review?.summary { summaryRow(s) }
                if session.exchanges.isEmpty {
                    // Сессии до COPILOT-06: только вопросы и подсказки.
                    ForEach(Array(session.turns.enumerated()), id: \.offset) { _, t in
                        ICCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(t.question).font(.system(size: 15, weight: .semibold))
                                MarkdownText(t.answer.isEmpty ? "Нет в базе" : t.answer, fontSize: 13)
                            }
                        }
                    }
                } else {
                    Text("Разбор вопросов (\(session.exchanges.count))").font(.system(size: 18, weight: .semibold))
                    ForEach(Array(session.exchanges.enumerated()), id: \.element.id) { i, e in exchangeCard(e, number: i + 1) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summaryRow(_ s: ReviewSummary) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Общее впечатление", systemImage: "lightbulb").font(.system(size: 15, weight: .semibold)).foregroundStyle(IC.ink)
                Text(s.overview).font(.system(size: 13)).foregroundStyle(IC.body).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !s.topics.isEmpty {
                    FlowChips(items: s.topics)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(IC.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 12) {
                bullets(isRegular ? "Договоренности" : "Сильные стороны", isRegular ? s.agreements : s.strengths,
                        icon: isRegular ? "checkmark.seal.fill" : "checkmark.circle.fill", color: IC.green)
                if !isRegular { bullets("Зоны для улучшения", s.weaknesses, icon: "exclamationmark.circle.fill", color: IC.red) }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(IC.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(IC.line))
            if !s.nextSteps.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Следующие шаги", systemImage: "flag").font(.system(size: 15, weight: .semibold)).foregroundStyle(IC.accent)
                    ForEach(Array(s.nextSteps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1)").font(.system(size: 12, weight: .semibold)).foregroundStyle(IC.accent)
                                .frame(width: 24, height: 24).background(IC.card, in: Circle())
                            Text(step).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                    }
                }
                .padding(16)
                .frame(width: 260, alignment: .topLeading)
                .background(IC.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    @ViewBuilder private func bullets(_ title: String, _ items: [String], icon: String, color: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(title) (\(items.count))").font(.system(size: 13, weight: .semibold))
                ForEach(items, id: \.self) { item in
                    Label { Text(item).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
                        icon: { Image(systemName: icon).foregroundStyle(color) }
                }
            }
        }
    }

    private func exchangeCard(_ e: SessionExchange, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(number)").font(.system(size: 13, weight: .semibold)).foregroundStyle(IC.accent)
                    .frame(width: 28, height: 28).background(IC.accent.opacity(0.1), in: Circle())
                Text(e.question).font(.system(size: 15, weight: .semibold)).textSelection(.enabled)
                Spacer()
                Text(clock(e.askedAt)).font(.system(size: 12).monospacedDigit()).foregroundStyle(IC.secondary)
            }
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isRegular ? "Вы сказали:" : "Вы ответили:").font(.system(size: 12, weight: .semibold)).foregroundStyle(IC.secondary)
                    Text(e.answerText.isEmpty ? "Ваш ответ не записан" : "«\(e.answerText)»")
                        .font(.system(size: 13)).foregroundStyle(e.answerText.isEmpty ? IC.secondary : IC.body)
                        .textSelection(.enabled)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(IC.background, in: RoundedRectangle(cornerRadius: 10))
                    if let hint = e.hint, !hint.isEmpty {
                        DisclosureGroup {
                            MarkdownText(hint, fontSize: 12).foregroundStyle(IC.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Label("Подсказка на экране", systemImage: "doc.text").font(.system(size: 12))
                        }
                        .padding(10)
                        .background(IC.card, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(IC.line))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                if let c = session.review?.comment(for: e.id) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Комментарий ИИ", systemImage: "sparkles").font(.system(size: 13, weight: .semibold)).foregroundStyle(IC.accent)
                        if !c.good.isEmpty { (Text("Хорошо: ").fontWeight(.semibold) + Text(c.good)).font(.system(size: 12)) }
                        if !c.missing.isEmpty { (Text("Не хватило: ").fontWeight(.semibold) + Text(c.missing)).font(.system(size: 12)) }
                        if !c.better.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Лучше сказать:").font(.system(size: 12, weight: .semibold)).foregroundStyle(IC.accent)
                                Text("«\(c.better)»").font(.system(size: 12)).textSelection(.enabled)
                            }
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(IC.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(IC.accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(IC.accent.opacity(0.12)))
                }
            }
        }
        .padding(16)
        .background(IC.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(IC.line))
    }

    private func clock(_ date: Date) -> String {
        TimelineEntry.clock(date.timeIntervalSince(session.startedAt))
    }

    // MARK: Расшифровка (P16)

    private var transcriptTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(IC.secondary)
                    TextField("Найти в расшифровке…", text: $search).textFieldStyle(.plain)
                }
                .padding(9)
                .background(IC.card, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(IC.line))
                Picker("Говорящие", selection: $speaker) {
                    Text("Все").tag(TimelineEntry.Speaker?.none)
                    Text(asker).tag(TimelineEntry.Speaker?.some(.interviewer))
                    Text("Вы").tag(TimelineEntry.Speaker?.some(.owner))
                }
                .frame(width: 170)
                Toggle("Подсказки", isOn: $showHints).toggleStyle(.checkbox)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    let q = search.trimmingCharacters(in: .whitespaces).lowercased()
                    let lines = session.timeline.filter { line in
                        (showHints || line.speaker != .hint)
                            && (speaker == nil || line.speaker == speaker || (line.speaker == .hint && speaker == nil))
                            && (q.isEmpty || line.text.lowercased().contains(q))
                    }
                    if lines.isEmpty { Text("Ничего не найдено").foregroundStyle(IC.secondary) }
                    ForEach(lines) { line in TranscriptBubble(line: line, asker: asker) }
                }
                .frame(maxWidth: 760, alignment: .leading)
            }
        }
    }

    // MARK: Спросить ИИ (P16)

    private var askTab: some View {
        let busy = reviews?.asking.contains(session.id) == true
        let chat = session.review?.chat ?? []
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Спросить ИИ").font(.system(size: 18, weight: .semibold))
                Circle().fill(reviews == nil ? IC.amber : IC.green).frame(width: 8, height: 8)
                Text("Отвечает по расшифровке и сводке этой сессии").font(.system(size: 12)).foregroundStyle(IC.secondary)
            }
            HStack(spacing: 10) {
                ForEach(suggestions, id: \.0) { text, icon in
                    Button { send(text) } label: {
                        Label(text, systemImage: icon).font(.system(size: 12)).foregroundStyle(IC.accent)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(IC.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(reviews == nil || busy)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if chat.isEmpty && !busy {
                        Text("Спросите о звонке — например, где ответы были слабее или что подготовить.").foregroundStyle(IC.secondary)
                    }
                    ForEach(chat) { qa in
                        HStack {
                            Spacer(minLength: 120)
                            Text(qa.question).font(.system(size: 13)).padding(12)
                                .background(IC.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        }
                        HStack(alignment: .top, spacing: 10) {
                            ICLogo(size: 30)
                            MarkdownText(qa.answer, fontSize: 13).textSelection(.enabled)
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(IC.card, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(IC.line))
                        }
                    }
                    if busy { HStack { ProgressView().controlSize(.small); Text("Думаю…").foregroundStyle(IC.secondary) } }
                    if let error = reviews?.askError[session.id] {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(IC.amber)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                TextField("Спросить что-то об этой сессии…", text: $question)
                    .textFieldStyle(.plain)
                    .onSubmit { send(question) }
                    .padding(12)
                    .background(IC.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(IC.line))
                Button { send(question) } label: { Image(systemName: "paperplane.fill").frame(width: 20, height: 20) }
                    .buttonStyle(ICButtonStyle(primary: true))
                    .disabled(busy || reviews == nil || question.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Спросить")
            }
        }
    }

    private var suggestions: [(String, String)] {
        isRegular
            ? [("О чем договорились?", "checkmark.seal"), ("Что мне сделать дальше?", "list.bullet"), ("Напиши письмо-итог", "envelope")]
            : [("Где я отвечал слабее всего?", "chart.bar"), ("Что подтянуть к следующему этапу?", "sparkles"), ("Напиши письмо-благодарность", "envelope")]
    }

    private func send(_ text: String) {
        guard let reviews, !reviews.asking.contains(session.id) else { return }
        reviews.ask(session.id, question: text)
        question = ""
    }
}

/// P16: реплика с аватаром; подсказка — пунктирной плашкой «Подсказка показана».
private struct TranscriptBubble: View {
    let line: TimelineEntry
    let asker: String
    @State private var open = false

    var body: some View {
        if line.speaker == .hint {
            DisclosureGroup(isExpanded: $open) {
                MarkdownText(line.text, fontSize: 12).foregroundStyle(IC.secondary).frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Подсказка показана · \(line.clock)", systemImage: "sparkles").font(.system(size: 12)).foregroundStyle(IC.ink)
            }
            .padding(10)
            .background(IC.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(IC.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .padding(.leading, 46)
        } else {
            let owner = line.speaker == .owner
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.fill").font(.system(size: 14)).foregroundStyle(owner ? .white : IC.secondary)
                    .frame(width: 34, height: 34)
                    .background(owner ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x4388FF), Color(hex: 0x7048E8)], startPoint: .top, endPoint: .bottom))
                                      : AnyShapeStyle(IC.line), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(owner ? "Вы" : asker).font(.system(size: 12, weight: .semibold))
                        Text(line.clock).font(.system(size: 11).monospacedDigit()).foregroundStyle(IC.secondary)
                    }
                    Text(line.text).font(.system(size: 13)).textSelection(.enabled)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(owner ? IC.accent.opacity(0.08) : IC.bubble, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Темы сводки — бейджами в строку с переносом.
private struct FlowChips: View {
    let items: [String]
    var body: some View {
        FlowLayout(spacing: 6) { ForEach(items, id: \.self) { ICBadge(text: $0, color: IC.secondary) } }
    }
}

/// Раскладка «в строку с переносом» для бейджей.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1] = (last.indices + [i], last.width + spacing + size.width, max(last.height, size.height))
            } else {
                rows.append(([i], size.width, size.height))
            }
        }
        return rows
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
