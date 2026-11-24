import Foundation

/// Отрезок сессии, когда владелец выключил свой микрофон в Copilot (COPILOT-18 D7).
/// Только время — без текста и звука. `end == nil` — микрофон выключен до сих пор (или сессия оборвалась).
public struct MicMutedInterval: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date?

    public init(start: Date, end: Date? = nil) {
        self.start = start
        self.end = end
    }

    /// Применить переключение: `muted == true` открывает отрезок (если последний ещё не открыт), `false` закрывает открытый.
    /// Повторное то же состояние ничего не меняет.
    public static func apply(muted: Bool, at now: Date, to intervals: inout [MicMutedInterval]) {
        if muted {
            guard intervals.last?.end != nil || intervals.isEmpty else { return }
            intervals.append(MicMutedInterval(start: now))
        } else if let last = intervals.indices.last, intervals[last].end == nil {
            intervals[last].end = max(now, intervals[last].start)
        }
    }

    /// Конец сессии: открытый отрезок закрывается временем окончания.
    public static func close(_ intervals: inout [MicMutedInterval], at now: Date) {
        apply(muted: false, at: now, to: &intervals)
    }

    /// Попадает ли момент в один из отрезков (включая границы; открытый отрезок идёт до `sessionEnd`/бесконечности).
    public static func contains(_ date: Date, in intervals: [MicMutedInterval]) -> Bool {
        intervals.contains { date >= $0.start && date <= ($0.end ?? .distantFuture) }
    }
}
