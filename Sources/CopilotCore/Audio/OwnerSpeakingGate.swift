import Foundation

/// «Владелец говорит» с учётом «Микрофон выкл.» (COPILOT-18). Детектор активности шлёт только переходы, поэтому сырое значение
/// помнится: если владелец включил микрофон посреди фразы, сигнал возвращается сразу, а не со следующего начала речи.
/// Возвращает новое значение для сообщения наружу или nil, если оно не изменилось относительно `current`.
public struct OwnerSpeakingGate: Sendable, Equatable {
    public private(set) var off = false
    private var raw = false

    public init() {}

    public mutating func detector(_ speaking: Bool, current: Bool) -> Bool? {
        raw = speaking
        let effective = speaking && !off
        return effective == current ? nil : effective
    }

    public mutating func setOff(_ value: Bool, current: Bool) -> Bool? {
        off = value
        let effective = raw && !off
        return effective == current ? nil : effective
    }
}
