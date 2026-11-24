import Foundation

/// Запущенное приложение — минимум данных для выбора источника звука.
public struct RunningAppInfo: Equatable, Sendable, Hashable {
    public var bundleID: String
    public var name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// Что именно захватывать.
public enum ResolvedAudioSource: Equatable, Sendable {
    case app(RunningAppInfo)
    case allSystem
    /// Микрофон Mac (режим самопроверки).
    case microphone
    /// Нет подходящего запущенного приложения (Auto) или выбранное приложение закрыто.
    case none

    public var displayName: String? {
        switch self {
        case .app(let a): a.name
        case .allSystem: "All system audio"
        case .microphone: "Microphone"
        case .none: nil
        }
    }
}

/// Выбор источника — R-01 + универсальный Быстрый старт.
/// Auto: первое запущенное приложение звонка (Zoom → Teams → Chrome → Telegram → Discord → Safari);
/// если ни одно не запущено — сразу «Весь системный звук» (никогда не блокирует с «Звонок не найден»).
public enum AudioSourceResolver {
    /// Порядок Auto. У Telegram два клиента: «Telegram» (App Store) и «Telegram Desktop».
    public static let autoPriority: [(bundleIDs: [String], name: String)] = [
        (["us.zoom.xos"], "Zoom"),
        (["com.microsoft.teams2", "com.microsoft.teams"], "Teams"),
        (["com.google.Chrome"], "Chrome"),
        (["ru.keepcoder.Telegram", "org.telegram.desktop"], "Telegram"),
        (["com.hnc.Discord"], "Discord"),
        (["com.apple.Safari"], "Safari"),
    ]

    public static func resolve(_ setting: AudioSourceSetting, running: [RunningAppInfo]) -> ResolvedAudioSource {
        switch setting {
        case .allSystem:
            return .allSystem
        case .microphone:
            return .microphone
        case .app(let bundleID, _):
            if let app = running.first(where: { $0.bundleID == bundleID }) { return .app(app) }
            return .none
        case .auto:
            for candidate in autoPriority {
                if let app = running.first(where: { candidate.bundleIDs.contains($0.bundleID) }) {
                    return .app(RunningAppInfo(bundleID: app.bundleID, name: candidate.name))
                }
            }
            return .allSystem
        }
    }

    /// Процессы, звук которых относится к приложению: само приложение и его помощники
    /// (`com.google.Chrome.helper…` — звук вкладок Chrome идёт из них).
    public static func belongsTo(_ bundleID: String, app: String) -> Bool {
        bundleID == app || bundleID.hasPrefix(app + ".")
    }

    /// COPILOT-16 R-06: запущенное приложение звонка по порядку Auto (для действия «Только звонок»).
    public static func runningCallApp(_ running: [RunningAppInfo]) -> RunningAppInfo? {
        for candidate in autoPriority {
            if let app = running.first(where: { candidate.bundleIDs.contains($0.bundleID) }) {
                return RunningAppInfo(bundleID: app.bundleID, name: candidate.name)
            }
        }
        return nil
    }

    /// COPILOT-16 R-06: предупреждение «слушаю весь звук Mac» — только для `.allSystem`; `callApp` — что предложить вместо.
    public struct AllSystemNotice: Equatable, Sendable {
        public var callApp: RunningAppInfo?
    }

    public static func allSystemNotice(for resolved: ResolvedAudioSource, running: [RunningAppInfo]) -> AllSystemNotice? {
        guard resolved == .allSystem else { return nil }
        return AllSystemNotice(callApp: runningCallApp(running))
    }
}
