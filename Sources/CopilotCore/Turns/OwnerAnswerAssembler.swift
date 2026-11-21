import Foundation

/// Ответ владельца, собранный из его фраз (COPILOT-15 R-11).
public struct OwnerAnswer: Sendable, Equatable {
    /// Номера фраз канала владельца: по ним строится звук для повторного распознавания.
    public var utterances: [Int]
    /// Склейка текстов фраз — предварительный текст, запасной при неудаче повторного распознавания.
    public var provisionalText: String
}

/// Собирает фразы канала владельца в один ответ: ответ закончен, когда владелец молчит ≥ `pauseMs`
/// (та же логика паузы, что у хода собеседника). Чистая логика со временем «снаружи» (мс).
public struct OwnerAnswerAssembler: Sendable {
    public var pauseMs: Double
    private var texts: [String] = []
    private var utterances: [Int] = []
    private var lastEnd: Double = 0

    public init(pauseMs: Double = 1000) { self.pauseMs = pauseMs }

    public var hasPending: Bool { !utterances.isEmpty }

    /// Фраза владельца прошла фильтры; `speechEnd` — её конец (мс).
    public mutating func phraseFinal(text: String, utterance: Int, speechEnd: Double) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        texts.append(t)
        utterances.append(utterance)
        lastEnd = max(lastEnd, speechEnd)
    }

    /// Готовый ответ, если пауза владельца достаточна и он сейчас не говорит.
    public mutating func tick(at now: Double, speaking: Bool) -> OwnerAnswer? {
        guard hasPending, !speaking, now - lastEnd >= pauseMs else { return nil }
        return flush()
    }

    /// Забрать накопленное сейчас (конец звонка, смена канала).
    public mutating func flush() -> OwnerAnswer? {
        guard hasPending else { return nil }
        defer { texts = []; utterances = []; lastEnd = 0 }
        return OwnerAnswer(utterances: utterances, provisionalText: texts.joined(separator: " "))
    }

    /// Выбросить накопленное (пауза, очистка).
    public mutating func reset() { texts = []; utterances = []; lastEnd = 0 }
}
