import CopilotCore
import Foundation

/// Текущая сессия и история (R-19). Сессия начинается при старте слушания и закрывается при выходе.
@MainActor
final class SessionController {
    let store = SessionStore(directory: AppPaths.sessions)
    private(set) var current: SessionRecord?
    private var saveTask: Task<Void, Never>?
    /// Текущий источник звука (имя приложения) — для сессии, начатой при запуске, когда источник ещё не выбран.
    var currentSource: () -> String? = { nil }

    /// «Сохранять расшифровку» выключено (COPILOT-09 R-01) — сессия живёт только в памяти, на диск не пишется.
    private var persist = true

    func start(source: String?, retentionDays: Int, config: SessionConfig? = nil) {
        store.restrictPermissions()
        let removed = store.purge(olderThan: retentionDays)
        if removed > 0 { Log.app.info("sessions purged: \(removed)") }
        current = store.newSession(source: source)
        current?.config = config
        persist = config?.saveTranscript ?? true
    }

    /// С COPILOT-09 сессия начинается кнопкой Start, а не с запуска приложения: время начала — момент Start.
    /// Источник, ещё не найденный при старте, записывается с первой репликой.
    private func touch() {
        guard current?.source == nil else { return }
        current?.source = currentSource()
    }

    func addUtterance(id: Int, text: String, language: String) {
        guard current != nil else { return }
        touch()
        current?.utterances.append(.init(id: id, text: text, language: language, at: Date()))
        scheduleSave()
    }

    /// Уточнённый итог реплики (R-37) заменяет её быстрый текст.
    func reviseUtterance(id: Int, text: String, language: String) {
        guard let i = current?.utterances.lastIndex(where: { $0.id == id }), let at = current?.utterances[i].at else { return }
        current?.utterances[i] = .init(id: id, text: text, language: language, at: at)
        scheduleSave()
    }

    /// Ваша фраза с временем — для расшифровки по говорящим (COPILOT-09 R-14).
    func addOwnerUtterance(_ text: String) {
        guard current != nil else { return }
        let id = (current?.ownerUtterances.last?.id ?? 0) + 1
        current?.ownerUtterances.append(.init(id: id, text: text, language: "", at: Date()))
        scheduleSave()
    }

    /// Уточненный текст вашей фразы (самопроверка) заменяет черновой — последнее совпадение.
    func reviseOwnerUtterance(_ fast: String, to text: String) {
        guard let i = current?.ownerUtterances.lastIndex(where: { $0.text == fast }), let u = current?.ownerUtterances[i] else { return }
        current?.ownerUtterances[i] = .init(id: u.id, text: text, language: u.language, at: u.at)
        scheduleSave()
    }

    /// Обмены интервью с ответами владельца (COPILOT-06) — снимок памяти текущего интервью.
    func updateExchanges(_ exchanges: [SessionExchange]) {
        guard current != nil else { return }
        if !exchanges.isEmpty { touch() }
        current?.exchanges = exchanges
        scheduleSave()
    }

    func addAnswer(_ r: AnswerController.AnswerRecord) {
        guard current != nil, r.turn.id >= 0 || r.turn.text == "Скриншот задачи" else { return }
        touch()
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
        guard persist, let s = current, !(s.utterances.isEmpty && s.turns.isEmpty && s.exchanges.isEmpty) else { return }
        do { try store.save(s) } catch { Log.app.error("session save failed: \(error.localizedDescription, privacy: .public)") }
    }

    /// Конец сессии: запись сохраняется (если разрешено) и возвращается для разбора (этап 4); текущей больше нет.
    @discardableResult
    func finish() -> SessionRecord? {
        saveTask?.cancel()
        current?.endedAt = Date()
        saveNow()
        let finished = current
        current = nil
        return finished
    }
}
