import Foundation

/// «Уточнение голосом» одним разом (COPILOT-18 D9): кнопка или ⇧⌘U взводит режим, СЛЕДУЮЩАЯ фраза владельца считается
/// уточнением текущего вопроса, после неё режим гаснет. Повторное нажатие отменяет. Настройка `ownerVoiceClarification` не меняется.
public struct VoiceClarifyArm: Sendable, Equatable {
    /// Без фразы режим гаснет сам через столько секунд (если владелец в этот момент не говорит — тогда ждём конца фразы).
    public static let timeoutSeconds: TimeInterval = 15

    public private(set) var armedAt: Date?
    public var isArmed: Bool { armedAt != nil }

    public init() {}

    /// Нажатие: взвести или отменить. Возвращает новое состояние «взведён».
    @discardableResult
    public mutating func toggle(now: Date) -> Bool {
        armedAt = isArmed ? nil : now
        return isArmed
    }

    public mutating func disarm() { armedAt = nil }

    /// Таймер: true, если режим только что погас по времени. Пока владелец говорит, режим держится (фраза ещё не дошла до `consume`).
    @discardableResult
    public mutating func expire(now: Date, ownerSpeaking: Bool) -> Bool {
        guard let at = armedAt, now.timeIntervalSince(at) >= Self.timeoutSeconds, !ownerSpeaking else { return false }
        armedAt = nil
        return true
    }

    /// Пришла фраза владельца. Если режим взведён — он расходуется (true) и фраза уточняет вопрос; перебитая фраза не расходует.
    public mutating func consume(interrupted: Bool) -> Bool {
        guard isArmed, !interrupted else { return false }
        armedAt = nil
        return true
    }
}

extension OwnerQuestionDetector {
    /// Решение для фразы, сказанной во взведённом режиме (D9). Предел — `forcedMaxWords` (40), а не `maxWords`. Сначала обычные правила
    /// `detect` с этим пределом (повтор вопроса целиком → `replaceLastQuestion`/`newQuestion`); если они молчат, любая содержательная
    /// фраза — поправка к активному вопросу (`clarifyLastQuestion`), а без активного вопроса — новый вопрос (`newQuestion`).
    /// Пустая фраза, заполнители/бэкченнелы («угу», «секунду») и фразы длиннее 40 слов — обычный ответ. Автоматический `detect` (D1) не затронут.
    public static func detectForced(text: String, secondsSinceLastQuestion: TimeInterval?, hasActiveQuestion: Bool) -> Decision {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.lowercased().split { !$0.isLetter && !$0.isNumber }
        guard !words.isEmpty, words.count <= forcedMaxWords else { return .none }
        let d = detect(text: trimmed, secondsSinceLastQuestion: secondsSinceLastQuestion, hasActiveQuestion: hasActiveQuestion,
                       wordLimit: forcedMaxWords)
        guard d == .none else { return d }
        guard !TurnDetector.isBackchannel(trimmed), !words.allSatisfy({ isFiller(String($0)) }) else { return .none }
        return hasActiveQuestion ? .clarifyLastQuestion(correction: trimmed) : .newQuestion(trimmed)
    }
}
