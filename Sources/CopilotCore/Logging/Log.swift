import os

/// Логи — R-24: `os_log`, subsystem `com.itmax04.interviewcopilot`.
/// Текст реплик и ответов в логи не пишется; только события, метрики и ошибки.
/// Метрики пишутся уровнем notice: info хранится только в памяти и к концу созвона пропадает (scripts/metrics.py).
public enum Log {
    public static let subsystem = "com.itmax04.interviewcopilot"
    public static let audio = Logger(subsystem: subsystem, category: "audio")
    public static let stt = Logger(subsystem: subsystem, category: "stt")
    public static let turns = Logger(subsystem: subsystem, category: "turns")
    public static let llm = Logger(subsystem: subsystem, category: "llm")
    public static let metrics = Logger(subsystem: subsystem, category: "metrics")
    public static let app = Logger(subsystem: subsystem, category: "app")
}
