import Foundation

/// Папки данных приложения — ADR-0001 п. 8: `~/Library/Application Support/InterviewCopilot/`.
public enum AppPaths {
    public static var root: URL {
        if let override = ProcessInfo.processInfo.environment["INTERVIEWCOPILOT_HOME"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InterviewCopilot", isDirectory: true)
    }

    public static var models: URL {
        if let override = ProcessInfo.processInfo.environment["INTERVIEWCOPILOT_MODELS_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return root.appendingPathComponent("models", isDirectory: true)
    }

    public static var parakeetModels: URL { models.appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true) }

    /// Старая единственная папка профиля (до COPILOT-08): переносится в `profiles/` при запуске.
    public static var profile: URL { root.appendingPathComponent("profile", isDirectory: true) }
    /// Профили владельца (COPILOT-08 R-01): `profiles/<id>/`.
    public static var profiles: URL { root.appendingPathComponent("profiles", isDirectory: true) }
    /// Общие инструкции для всех профилей и режима «Без профиля» (COPILOT-08 R-04).
    public static var generalInstructions: URL { root.appendingPathComponent("instructions.md") }
    public static var sessions: URL { root.appendingPathComponent("sessions", isDirectory: true) }
    public static var cache: URL { root.appendingPathComponent("cache", isDirectory: true) }

    public static func model(_ file: String) -> URL { models.appendingPathComponent(file) }
}
