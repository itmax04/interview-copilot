import Foundation
import Testing
@testable import CopilotCore

@Suite("SessionStore — R-19, AC-12")
struct SessionStoreTests {
    func makeStore() -> (SessionStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sessions-\(UUID().uuidString)")
        return (SessionStore(directory: dir), dir)
    }

    func sample(_ store: SessionStore, at date: Date) -> SessionRecord {
        var s = store.newSession(source: "Chrome", at: date)
        s.utterances.append(.init(id: 1, text: "Расскажите о себе", language: "ru", at: date))
        s.turns.append(.init(id: 1, question: "Расскажите о себе", answer: "• 7 лет", source: "bank", model: nil, cardID: "about-me",
                             forced: false, cardShownMs: 420, firstTokenMs: nil, inputTokens: nil, outputTokens: nil, at: date))
        s.endedAt = date.addingTimeInterval(600)
        return s
    }

    @Test func saveListLoad() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let date = Date(timeIntervalSince1970: 1_791_000_000)
        let s = sample(store, at: date)
        try store.save(s)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(s.id).json").path))
        #expect(s.id.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}$"#, options: .regularExpression) != nil)
        #expect(store.list() == [s])
        #expect(store.load(s.id) == s)
        // Повторное сохранение той же сессии обновляет файл, а не создаёт новый.
        var updated = s
        updated.turns[0].answer = "• обновлено"
        try store.save(updated)
        #expect(store.list().count == 1)
        #expect(store.load(s.id)?.turns[0].answer == "• обновлено")
    }

    @Test func uniqueIdsForSameSecond() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let date = Date()
        let a = store.newSession(source: nil, at: date)
        try store.save(a)
        let b = store.newSession(source: nil, at: date)
        #expect(a.id != b.id)
    }

    @Test func deleteOneAndAll() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let s1 = sample(store, at: Date(timeIntervalSince1970: 1_791_000_000))
        try store.save(s1)
        let s2 = sample(store, at: Date(timeIntervalSince1970: 1_791_100_000))
        try store.save(s2)
        #expect(store.list().map(\.id) == [s2.id, s1.id]) // новые сверху
        try store.delete(s1.id)
        #expect(store.list().map(\.id) == [s2.id])
        try store.deleteAll()
        #expect(store.list().isEmpty)
    }

    @Test func purgeByRetention() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date(timeIntervalSince1970: 1_791_300_000)
        let old = sample(store, at: now.addingTimeInterval(-31 * 86_400 - 700))
        try store.save(old)
        let fresh = sample(store, at: now.addingTimeInterval(-29 * 86_400))
        try store.save(fresh)
        #expect(store.purge(olderThan: 30, now: now) == 1)
        #expect(store.list().map(\.id) == [fresh.id])
    }

    @Test func noAudioFields() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let json = String(decoding: try SessionStore.encoder.encode(sample(store, at: Date())), as: UTF8.self)
        #expect(!json.contains("audio") && !json.contains("samples")) // R-04
    }
}

@Suite("UsageMeter — R-20, R-18 Budget")
struct UsageMeterTests {
    static let pricing = try! Pricing.load(URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../Resources/pricing.json").standardized)

    func utc(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s)!
    }

    @Test func pricesFromSpec() {
        let p = Self.pricing
        let million = TokenUsage(input: 1_000_000, output: 1_000_000)
        #expect(abs(p.cost(provider: .anthropic, model: "claude-sonnet-5-5", usage: million, at: Date(), geminiFreeTier: true) - 12) < 1e-9)
        #expect(abs(p.cost(provider: .anthropic, model: "claude-haiku-4-5", usage: million, at: Date(), geminiFreeTier: true) - 6) < 1e-9)
        #expect(abs(p.cost(provider: .gemini, model: "gemini-3.8-flash", usage: million, at: Date(), geminiFreeTier: false) - 4.5) < 1e-9)
        #expect(p.cost(provider: .gemini, model: "gemini-3.8-flash", usage: million, at: Date(), geminiFreeTier: true) == 0)
    }

    @Test func deepseekPeakAndOffPeak() {
        let p = Self.pricing
        let million = TokenUsage(input: 1_000_000, output: 1_000_000)
        // Вторник 2026-10-06 02:00 UTC — пик; 12:00 UTC — вне пика; суббота — вне пика.
        #expect(p.isDeepSeekPeak(utc("2026-10-06T02:00:00Z")))
        #expect(!p.isDeepSeekPeak(utc("2026-10-06T12:00:00Z")))
        #expect(!p.isDeepSeekPeak(utc("2026-10-10T02:00:00Z")))
        #expect(abs(p.cost(provider: .deepseek, model: "deepseek-flash", usage: million, at: utc("2026-10-06T02:00:00Z"), geminiFreeTier: true) - 1.5) < 1e-9)
        #expect(abs(p.cost(provider: .deepseek, model: "deepseek-flash", usage: million, at: utc("2026-10-06T12:00:00Z"), geminiFreeTier: true) - 0.75) < 1e-9)
    }

    @Test func cachedTokensNotDoubleCounted() {
        let p = Self.pricing
        // Gemini: promptTokenCount уже включает кэш → 1М входа, из них 1М из кэша = цена кэша, а не вход + кэш.
        let g = p.cost(provider: .gemini, model: "gemini-3.8-flash", usage: TokenUsage(input: 1_000_000, output: 0, cachedInput: 1_000_000), at: Date(), geminiFreeTier: false)
        #expect(abs(g - 0.75) < 1e-9)
        // Anthropic: input_tokens без кэша, кэш отдельно.
        let a = p.cost(provider: .anthropic, model: "claude-sonnet-5-5", usage: TokenUsage(input: 1_000_000, output: 0, cachedInput: 1_000_000), at: Date(), geminiFreeTier: true)
        #expect(abs(a - 2.2) < 1e-9)
    }

    @Test func countersAndStatusLine() {
        var clock = utc("2026-10-06T12:00:00Z")
        let meter = UsageMeter(pricing: Self.pricing, storage: nil, now: { clock })
        let s = AppSettings()
        meter.record(provider: .gemini, model: "gemini-3.8-flash", usage: TokenUsage(input: 1000, output: 100), settings: s)
        meter.record(provider: .anthropic, model: "claude-sonnet-5-5", usage: TokenUsage(input: 10_000, output: 1000), settings: s)
        #expect(meter.statusLine == "Today: $0.03 · Gemini: 1 req")
        meter.recordError(provider: .gemini, error: .http(status: 429, message: ""))
        #expect(meter.statusLine == "Today: $0.03 · Gemini: limit")
        // Новый день — дневные счётчики с нуля, месячный копится.
        clock = utc("2026-10-07T12:00:00Z")
        #expect(meter.statusLine == "Today: $0.00 · Gemini: 0 req")
        #expect(abs(meter.state.monthCost - 0.03) < 1e-9)
    }

    @Test func budgetLimitReached() {
        let meter = UsageMeter(pricing: Self.pricing, storage: nil, now: { Date() })
        var s = AppSettings()
        s.monthlyBudgetUSD = 0.05
        #expect(meter.record(provider: .anthropic, model: "claude-sonnet-5-5", usage: TokenUsage(input: 10_000, output: 1000), settings: s) == false)
        #expect(meter.record(provider: .anthropic, model: "claude-sonnet-5-5", usage: TokenUsage(input: 10_000, output: 1000), settings: s) == true)
        // После «Включить снова» владельцем лимит не срабатывает повторно в этом месяце (ревью P-13).
        #expect(meter.record(provider: .gemini, model: "gemini-3.8-flash", usage: TokenUsage(input: 1, output: 1), settings: s) == false)
        #expect(meter.record(provider: .anthropic, model: "claude-sonnet-5-5", usage: TokenUsage(input: 10_000, output: 1000), settings: s) == false)
        // Бесплатный Gemini в лимит не входит.
        let free = UsageMeter(pricing: Self.pricing, storage: nil, now: { Date() })
        for _ in 0..<100 { #expect(free.record(provider: .gemini, model: "gemini-3.8-flash", usage: TokenUsage(input: 100_000, output: 10_000), settings: s) == false) }
    }

    @Test func persistsBetweenLaunches() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("usage-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let a = UsageMeter(pricing: Self.pricing, storage: url)
        a.record(provider: .gemini, model: "gemini-3.8-flash", usage: TokenUsage(input: 1, output: 1), settings: AppSettings())
        let b = UsageMeter(pricing: Self.pricing, storage: url)
        #expect(b.statusLine.hasSuffix("Gemini: 1 req"))
    }
}
