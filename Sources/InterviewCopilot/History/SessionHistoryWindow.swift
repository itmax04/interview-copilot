import AppKit
import CopilotCore
import SwiftUI

/// Окно «Session history…» — R-19: список, просмотр, удаление одной или всех сессий.
@MainActor
final class SessionHistoryWindowController {
    private var window: NSWindow?
    private let sessions: SessionController

    init(sessions: SessionController) {
        self.sessions = sessions
    }

    func show() {
        sessions.saveNow()
        let view = SessionHistoryView(store: sessions.store)
        if let window {
            window.contentViewController = NSHostingController(rootView: view)
        } else {
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Session history"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 820, height: 540))
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
    @State private var sessions: [SessionRecord] = []
    @State private var selection: String?
    @State private var confirmDeleteAll = false

    var body: some View {
        NavigationSplitView {
            List(sessions, selection: $selection) { s in
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.startedAt.formatted(date: .abbreviated, time: .shortened))
                    Text("\(s.source ?? "—") · \(RussianPlural.questions(s.turns.count))").font(.caption).foregroundStyle(.secondary)
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
                SessionDetail(session: s) { delete(s.id) }
            } else {
                Text(sessions.isEmpty ? "История пуста" : "Выберите сессию").foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: reload)
        .confirmationDialog("Удалить всю историю сессий?", isPresented: $confirmDeleteAll) {
            Button("Удалить всё", role: .destructive) {
                try? store.deleteAll()
                reload()
            }
        }
    }

    private func reload() {
        sessions = store.list()
        if selection == nil { selection = sessions.first?.id }
    }

    private func delete(_ id: String) {
        try? store.delete(id)
        if selection == id { selection = nil }
        reload()
    }
}

struct SessionDetail: View {
    let session: SessionRecord
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(session.startedAt.formatted(date: .long, time: .shortened)).font(.title3.bold())
                    Spacer()
                    Button("Удалить сессию", role: .destructive, action: onDelete)
                }
                ForEach(Array(session.turns.enumerated()), id: \.offset) { _, t in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.question).font(.headline)
                        Text(t.answer.isEmpty ? "Нет в базе" : t.answer).textSelection(.enabled)
                        Text(meta(t)).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                }
                // COPILOT-06/07: что вы ответили на вопросы (микрофон на созвоне или ⌃⌥A в самопроверке).
                let answered = session.exchanges.filter { !$0.answer.isEmpty }
                if !answered.isEmpty {
                    Text("Ваши ответы").font(.headline).padding(.top, 6)
                    ForEach(answered) { e in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(e.question).font(.callout.weight(.semibold))
                            Text("Вы: \(e.answerText)").font(.callout).textSelection(.enabled)
                        }
                    }
                }
                if !session.utterances.isEmpty {
                    Text("Расшифровка").font(.headline).padding(.top, 6)
                    ForEach(Array(session.utterances.enumerated()), id: \.offset) { _, u in
                        Text("\(u.language.uppercased()): \(u.text)").font(.callout).textSelection(.enabled)
                    }
                }
            }
            .padding(20)
        }
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
