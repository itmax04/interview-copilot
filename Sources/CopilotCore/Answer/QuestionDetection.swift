import Foundation

/// Статус распознавания вопроса в оверлее — COPILOT-09 R-08, AC-04: видно, что делает автоматика.
public enum QuestionDetection: Equatable, Sendable {
    case idle
    /// Собеседник замолчал — ждем конца вопроса, опережающий запрос уже идет.
    case checking
    case detected
    /// Модель решила, что это не вопрос — ответить можно вручную.
    case notQuestion

    public enum Event: Equatable, Sendable {
        /// Собеседник снова заговорил — прежний статус устарел.
        case speechStarted
        /// Законченная реплика до истечения паузы (опережающий запрос).
        case draftReady
        case turnCompleted
        /// Модель ответила «—».
        case notAQuestion
        /// Clear, начало или конец сессии.
        case reset
    }

    public func next(on event: Event) -> QuestionDetection {
        switch event {
        case .speechStarted, .reset: .idle
        case .draftReady: .checking
        case .turnCompleted: .detected
        case .notAQuestion: .notQuestion
        }
    }

    /// Что показывает пилюля над карточкой (P02): пока у нового вопроса нет текста — «Готовлю ответ…», иначе статус.
    public enum Display: Equatable, Sendable {
        case hidden, checking, detected, notQuestion, preparing
    }

    /// `answerWaiting` — у показанного (последнего) вопроса запрос отправлен, текста еще нет.
    public func display(answerWaiting: Bool) -> Display {
        if answerWaiting { return .preparing }
        switch self {
        case .idle: return .hidden
        case .checking: return .checking
        case .detected: return .detected
        case .notQuestion: return .notQuestion
        }
    }
}

extension SessionPhase {
    public var isFailed: Bool { if case .failed = self { true } else { false } }
    /// Start — без сессии или после ошибки (AC-01: повторный Start не создает вторую сессию).
    public var canStart: Bool { self == .none || isFailed }
    /// End — только у идущей сессии (повторный End ничего не делает).
    public var canEnd: Bool { self == .active }
}

extension SessionConfig {
    /// Указания из чата «На всю сессию» (R-10) — после указаний мастера, каждое с новой строки.
    public func withSessionNotes(_ notes: [String]) -> SessionConfig {
        var c = self
        let extra = notes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
        if !extra.isEmpty { c.instructions = [c.instructions, extra].filter { !$0.isEmpty }.joined(separator: "\n") }
        return c
    }
}
