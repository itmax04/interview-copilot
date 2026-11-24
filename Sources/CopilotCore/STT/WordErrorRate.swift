import Foundation

/// Word error rate for the `stt-dense` eval (COPILOT-15 AC-01): case, punctuation and «ё/е» differences do not count.
public enum WordErrorRate {
    public static func words(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "ʼ", with: "'")
            .split { !($0.isLetter || $0.isNumber || $0 == "'") }
            .map(String.init)
    }

    /// Word-level edit distance (substitutions, insertions, deletions).
    public static func errors(reference: String, hypothesis: String) -> Int {
        let r = words(reference), h = words(hypothesis)
        if r.isEmpty { return h.count }
        if h.isEmpty { return r.count }
        var previous = Array(0...h.count)
        for i in 1...r.count {
            var row = [i] + [Int](repeating: 0, count: h.count)
            for j in 1...h.count {
                row[j] = min(previous[j] + 1, row[j - 1] + 1, previous[j - 1] + (r[i - 1] == h[j - 1] ? 0 : 1))
            }
            previous = row
        }
        return previous[h.count]
    }

    public static func referenceWords(_ text: String) -> Int { words(text).count }
}
