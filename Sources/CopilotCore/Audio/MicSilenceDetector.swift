import Foundation

/// «Микрофон не даёт звука» — COPILOT-16 R-05. Чистая логика: пик микрофона, флаг mute и время → уведомление вкл/выкл.
///
/// Цифровой ноль (≤ −119 дБ) дольше `silenceSeconds` при включённом канале микрофона и выключенном mute macOS — признак того,
/// что вход держит другое приложение или выбран не тот вход. При mute приоритет у баннера mute (уведомление не показывается).
/// Эпизод — непрерывный отрезок тишины; в журнал пишется один раз за эпизод.
public struct MicSilenceDetector: Sendable, Equatable {
    public static let silenceThresholdDB: Float = -119
    public static let silenceSeconds: Double = 10

    /// Уведомление показывается сейчас.
    public private(set) var isSilent = false
    /// Секунд тишины в текущем эпизоде на момент показа (для журнала и текста).
    public private(set) var silentSeconds: Double = 0
    private var silenceStart: Double?

    public init() {}

    public mutating func reset() { self = MicSilenceDetector() }

    /// Очередной замер. `active` — микрофон должен звучать (канал владельца включён или источник — микрофон, сессия слушает).
    /// Возвращает true ровно один раз за эпизод — в момент, когда уведомление появилось (пора писать `mic_silent`).
    @discardableResult
    public mutating func update(levelDB: Float, muted: Bool, active: Bool, now: Double) -> Bool {
        guard active, !muted, levelDB <= Self.silenceThresholdDB else {
            reset()
            return false
        }
        let start = silenceStart ?? now
        silenceStart = start
        silentSeconds = now - start
        guard silentSeconds >= Self.silenceSeconds else { return false }
        let began = !isSilent
        isSilent = true
        return began
    }
}
