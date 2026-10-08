import Foundation

/// Одинаковая нормализация и WER для всех движков: без регистра и пунктуации.
/// Разное написание чисел не приравнивается автоматически.
public struct TranscriptComparison: Codable, Sendable, Equatable {
    public let referenceWords: Int
    public let errors: Int
    public var wordErrorRate: Double { referenceWords == 0 ? 0 : Double(errors) / Double(referenceWords) }

    public init(reference: String, recognized: String) {
        let expected = Self.words(reference)
        let actual = Self.words(recognized)
        referenceWords = expected.count
        var previous = Array(0...actual.count)
        for (i, word) in expected.enumerated() {
            var current = [i + 1]
            for (j, token) in actual.enumerated() {
                current.append(min(current[j] + 1, previous[j + 1] + 1, previous[j] + (word == token ? 0 : 1)))
            }
            previous = current
        }
        errors = previous[actual.count]
    }

    public static func words(_ text: String) -> [String] {
        let normalized = text.lowercased().replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "ʼ", with: "'")
        let pattern = #"[\p{L}\p{N}]+(?:'[\p{L}\p{N}]+)*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized))
            .compactMap { Range($0.range, in: normalized).map { String(normalized[$0]) } }
    }
}
