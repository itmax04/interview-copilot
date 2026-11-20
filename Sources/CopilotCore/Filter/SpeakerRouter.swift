import Foundation

/// Куда идёт итог реплики в режиме «Микрофон Mac».
public enum MicPhraseRoute: Equatable, Sendable {
    /// Обычный путь вопроса: строка расшифровки, фильтр языка, ход, подсказка.
    case question
    /// Ответ владельца в память интервью (COPILOT-06), для хода — как шум.
    case ownerAnswer
}

/// Маршрут реплик микрофона в самопроверке (COPILOT-05 Q13, COPILOT-06 R-08).
///
/// По умолчанию (репетиция выключена) всё, что прошло проверку голоса, — вопрос; ⌃⌥A переключает в ответ.
/// Репетиция с собеседником (`rehearsal`, настройка `rehearsalWithInterviewer`): чужой голос — вопрос, голос владельца —
/// ответ без ⌃⌥A. ⌃⌥A остаётся ручным переключателем: пока он включён, любая реплика — ответ (ошибка порога не мешает
/// ответить). Реплика без вердикта (речи меньше 0,5 с, модель CAM++ не загружена, нет образца) идёт по состоянию ⌃⌥A.
public struct SpeakerRouter: Sendable {
    public var rehearsal = false
    /// Вердикт по номеру реплики: `TranscriptEvent.speaker` приходит раньше `revising` и `final`.
    private var owners: [Int: Bool] = [:]
    static let capacity = 20

    public init(rehearsal: Bool = false) { self.rehearsal = rehearsal }

    public mutating func noteSpeaker(utterance: Int, owner: Bool) {
        owners[utterance] = owner
        if owners.count > Self.capacity, let oldest = owners.keys.min() { owners.removeValue(forKey: oldest) }
    }

    /// Маршрут реплики; вердикт не забывается (по нему же решается `revising`), см. `forget`.
    public func route(utterance: Int, ownerAnswering: Bool) -> MicPhraseRoute {
        if ownerAnswering { return .ownerAnswer }
        guard rehearsal, let owner = owners[utterance] else { return .question }
        return owner ? .ownerAnswer : .question
    }

    /// Итог реплики обработан.
    public mutating func forget(utterance: Int) { owners.removeValue(forKey: utterance) }

    public mutating func reset() { owners.removeAll() }
}
