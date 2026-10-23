import Foundation

/// Что владелец уже сказал вслух на созвоне — COPILOT-05 R-07, S-07. Только в памяти: не показывается в панели и не
/// сохраняется в истории (Q6); в промпт — до 3 последних фраз за `window` секунд, не длиннее `maxCharacters`.
public struct CandidateContext: Sendable, Equatable {
    public static let maxPhrases = 3
    public static let maxCharacters = 600
    /// Фразы старше — уже не про текущий вопрос.
    public static let window: Double = 180

    private var phrases: [(text: String, at: Double)] = []

    public init() {}

    public mutating func add(_ text: String, at t: Double) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        phrases.append((trimmed, t))
        if phrases.count > 20 { phrases.removeFirst(phrases.count - 20) }
    }

    public mutating func clear() { phrases.removeAll() }

    /// Последние фразы (по порядку), уложенные в лимит символов: при переполнении отбрасываются самые старые.
    public func recent(at now: Double) -> [String] {
        var out: [String] = []
        var total = 0
        for p in phrases.reversed() where now - p.at <= Self.window * 1000 {
            guard out.count < Self.maxPhrases, total + p.text.count <= Self.maxCharacters else { break }
            out.insert(p.text, at: 0)
            total += p.text.count
        }
        return out
    }

    public static func == (a: CandidateContext, b: CandidateContext) -> Bool {
        a.phrases.map(\.text) == b.phrases.map(\.text) && a.phrases.map(\.at) == b.phrases.map(\.at)
    }
}
