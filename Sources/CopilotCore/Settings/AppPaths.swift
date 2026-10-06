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

    public static var profile: URL { root.appendingPathComponent("profile", isDirectory: true) }
    public static var sessions: URL { root.appendingPathComponent("sessions", isDirectory: true) }
    public static var cache: URL { root.appendingPathComponent("cache", isDirectory: true) }

    public static func model(_ file: String) -> URL { models.appendingPathComponent(file) }
}
