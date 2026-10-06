import Foundation

/// Eval `bank` — AC-04 (evals/README.md): точность top-1 на перефразировках, ложные совпадения вне базы, точность top-3.
public enum BankEval {
    public struct Case: Decodable, Sendable {
        public var q: String
        public var lang: String
        public var expected: String?
    }

    public struct Row: Sendable {
        public var q: String
        public var lang: String
        public var expected: String?
        public var top: [CardScore]
    }

    public struct Summary: Sendable {
        public var threshold: Double
        public var inBank: Int
        public var top1Correct: Int
        public var top3Correct: Int
        public var outOfBank: Int
        public var falseMatches: Int
        public var perLanguage: [String: (total: Int, correct: Int)]
        public var failures: [String]

        public var top1Accuracy: Double { inBank == 0 ? 0 : Double(top1Correct) / Double(inBank) }
        public var top3Accuracy: Double { inBank == 0 ? 0 : Double(top3Correct) / Double(inBank) }
        public var falseMatchRate: Double { outOfBank == 0 ? 0 : Double(falseMatches) / Double(outOfBank) }
        /// AC-04: ≥ 85% и ≤ 10%.
        public var passed: Bool { top1Accuracy >= 0.85 && falseMatchRate <= 0.10 }
    }

    public static func load(_ url: URL) throws -> [Case] {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { try JSONDecoder().decode(Case.self, from: Data($0.utf8)) }
    }

    /// Ранжирование всех случаев (дорогая часть — эмбеддинги); порог применяется потом, чтобы подбирать его без пересчёта.
    public static func rank(_ cases: [Case], index: BankIndex, builder: BankIndexBuilder) throws -> [Row] {
        try cases.map { c in
            let v = try builder.embedQuery(c.q)
            return Row(q: c.q, lang: c.lang, expected: c.expected, top: index.match(v, threshold: 2).top)
        }
    }

    /// Совпадение засчитывается, только если лучшая карточка выше порога и это нужная карточка.
    public static func summarize(_ rows: [Row], threshold: Double) -> Summary {
        var s = Summary(threshold: threshold, inBank: 0, top1Correct: 0, top3Correct: 0, outOfBank: 0, falseMatches: 0,
                        perLanguage: [:], failures: [])
        for r in rows {
            let best = r.top.first
            if let expected = r.expected {
                s.inBank += 1
                let ok = best?.card.id == expected && (best?.score ?? 0) >= threshold
                if ok { s.top1Correct += 1 } else {
                    s.failures.append(String(format: "MISS [%@] «%@» → %@ %.3f (ожидалось %@)", r.lang, r.q,
                                             best?.card.id ?? "—", best?.score ?? 0, expected))
                }
                if r.top.contains(where: { $0.card.id == expected }) { s.top3Correct += 1 }
                var lang = s.perLanguage[r.lang] ?? (0, 0)
                lang.total += 1
                if ok { lang.correct += 1 }
                s.perLanguage[r.lang] = lang
            } else {
                s.outOfBank += 1
                if let best, best.score >= threshold {
                    s.falseMatches += 1
                    s.failures.append(String(format: "FALSE [%@] «%@» → %@ %.3f", r.lang, r.q, best.card.id, best.score))
                }
            }
        }
        return s
    }

    /// Порог с наилучшим балансом: максимум (top-1 − ложные), при равенстве — выше порог (меньше ложных срабатываний).
    public static func bestThreshold(_ rows: [Row], range: [Double]) -> Summary {
        range.map { summarize(rows, threshold: $0) }
            .max { a, b in
                let sa = a.top1Accuracy - a.falseMatchRate, sb = b.top1Accuracy - b.falseMatchRate
                return sa == sb ? a.threshold < b.threshold : sa < sb
            }!
    }
}
