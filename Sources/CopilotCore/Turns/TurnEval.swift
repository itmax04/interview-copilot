import Foundation

/// Eval `turn` (evals/README.md): прогон `TurnDetector` по синтетическим таймлайнам.
/// Строка `evals/turn/cases.jsonl`:
/// `{"id": "...", "segments": [[текст, начало_мс, конец_мс], …], "expected_turn_at": мс | null,
///   "owner": [[с, по], …], "force_at": мс}`. Сегмент из двух элементов `[текст, t]` — начало = конец = t.
/// Итоговый текст фразы приходит через `finalDelayMs` после конца речи (как у распознавания, P-04: ~0,5 с).
public enum TurnEval {
    public struct Case: Decodable, Sendable {
        public var id: String
        public var segments: [[Segment]]
        public var expected_turn_at: Double?
        public var owner: [[Double]]?
        public var force_at: Double?

        public enum Segment: Decodable, Sendable {
            case text(String)
            case time(Double)

            public init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let s = try? c.decode(String.self) { self = .text(s) } else { self = .time(try c.decode(Double.self)) }
            }
        }

        var phrases: [(text: String, start: Double, end: Double)] {
            segments.compactMap { seg in
                guard case .text(let text)? = seg.first else { return nil }
                let times = seg.dropFirst().compactMap { if case .time(let t) = $0 { t } else { nil } }
                guard let first = times.first else { return nil }
                return (text, first, times.count > 1 ? times[1] : first)
            }
        }
    }

    public struct CaseResult: Sendable {
        public var id: String
        public var expected: Double?
        public var firedAt: Double?
        public var premature: Bool
        public var missed: Bool
        public var forced: Bool
    }

    public struct Summary: Sendable {
        public var cases: Int
        public var premature: Int
        public var missed: Int
        public var withExpected: Int
        public var meanLatencyMs: Double
        public var results: [CaseResult]

        public var prematureRate: Double { cases == 0 ? 0 : Double(premature) / Double(cases) }
        public var missedRate: Double { withExpected == 0 ? 0 : Double(missed) / Double(withExpected) }
        /// Пороги evals/README.md: преждевременные ≤ 10%, пропущенные ≤ 5%.
        public var passed: Bool { prematureRate <= 0.10 && missedRate <= 0.05 }
    }

    public static func load(_ url: URL) throws -> [Case] {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { try JSONDecoder().decode(Case.self, from: Data($0.utf8)) }
    }

    public static func run(_ cases: [Case], config: TurnDetector.Config = .init(), finalDelayMs: Double = 500) -> Summary {
        var results: [CaseResult] = []
        var latencies: [Double] = []
        for c in cases {
            var d = TurnDetector(config: config)
            enum E { case start, stop, final(String, Double), owner(Bool), force }
            var events: [(Double, Int, E)] = []
            for p in c.phrases {
                events.append((p.start, 0, .start))
                events.append((p.end, 1, .stop))
                events.append((p.end + finalDelayMs, 2, .final(p.text, p.end)))
            }
            for o in c.owner ?? [] where o.count == 2 {
                events.append((o[0], 3, .owner(true)))
                events.append((o[1], 3, .owner(false)))
            }
            if let f = c.force_at { events.append((f, 4, .force)) }
            events.sort { ($0.0, $0.1) < ($1.0, $1.1) }
            let horizon = (events.last?.0 ?? 0) + 4000
            var fired: [Turn] = []
            var i = 0
            var t: Double = 0
            while t <= horizon {
                while i < events.count, events[i].0 <= t {
                    switch events[i].2 {
                    case .start: d.interviewerStartedSpeaking(at: t)
                    case .stop: d.interviewerStoppedSpeaking(at: t)
                    case .final(let text, let end):
                        d.phraseFinal(text, speechEnd: end)
                        if let turn = d.takeRequestedForce(at: t) { fired.append(turn) }
                    case .owner(let on): d.setOwnerSpeaking(on, at: t)
                    case .force: if let turn = d.force(at: t) { fired.append(turn) }
                    }
                    i += 1
                }
                if let turn = d.tick(at: t) { fired.append(turn) }
                t += 10
            }
            let first = fired.first
            var premature = false
            var missed = false
            if let expected = c.expected_turn_at {
                if let f = first {
                    if f.firedAt < expected { premature = true }
                    // Вопрос обрезан: ход без последней фразы — тоже преждевременный.
                    if !f.forced, let last = c.phrases.last, !f.text.contains(last.text) { premature = true }
                    let limit = expected + config.thresholdMs + config.continuationExtraMs + finalDelayMs + 100
                    if f.firedAt > limit { missed = true }
                    if !f.forced, !premature { latencies.append(f.firedAt - expected) }
                } else {
                    missed = true
                }
            } else if first != nil {
                premature = true
            }
            results.append(CaseResult(id: c.id, expected: c.expected_turn_at, firedAt: first?.firedAt,
                                      premature: premature, missed: missed, forced: first?.forced ?? false))
        }
        return Summary(cases: cases.count, premature: results.filter(\.premature).count,
                       missed: results.filter(\.missed).count,
                       withExpected: cases.filter { $0.expected_turn_at != nil }.count,
                       meanLatencyMs: latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count),
                       results: results)
    }
}
