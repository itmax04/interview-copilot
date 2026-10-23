import CopilotCore
import Foundation

/// Текущая сессия и история (R-19). Сессия начинается при старте слушания и закрывается при выходе.
@MainActor
final class SessionController {
    let store = SessionStore(directory: AppPaths.sessions)
    private(set) var current: SessionRecord?
    private var saveTask: Task<Void, Never>?

    func start(source: String?, retentionDays: Int) {
        let removed = store.purge(olderThan: retentionDays)
        if removed > 0 { Log.app.info("sessions purged: \(removed)") }
        current = store.newSession(source: source)
    }

    func addUtterance(id: Int, text: String, language: String) {
        guard current != nil else { return }
        current?.utterances.append(.init(id: id, text: text, language: language, at: Date()))
        scheduleSave()
    }

    /// Уточнённый итог реплики (R-37) заменяет её быстрый текст.
    func reviseUtterance(id: Int, text: String, language: String) {
        guard let i = current?.utterances.lastIndex(where: { $0.id == id }), let at = current?.utterances[i].at else { return }
        current?.utterances[i] = .init(id: id, text: text, language: language, at: at)
        scheduleSave()
    }

    func addAnswer(_ r: AnswerController.AnswerRecord) {
        guard current != nil, r.turn.id >= 0 || r.turn.text == "Скриншот задачи" else { return }
        current?.turns.append(.init(id: r.turn.id, question: r.turn.text, answer: r.text, source: r.source, model: r.model,
                                    cardID: r.cardID, forced: r.turn.forced, cardShownMs: r.cardShownMs, firstTokenMs: r.firstTokenMs,
                                    inputTokens: r.usage?.input, outputTokens: r.usage?.output, at: Date()))
        scheduleSave()
    }

    /// Сохранение не чаще раза в 2 с; пустые сессии не сохраняются.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard let s = current, !(s.utterances.isEmpty && s.turns.isEmpty) else { return }
        do { try store.save(s) } catch { Log.app.error("session save failed: \(error.localizedDescription, privacy: .public)") }
    }

    func finish() {
        saveTask?.cancel()
        current?.endedAt = Date()
        saveNow()
    }
}
