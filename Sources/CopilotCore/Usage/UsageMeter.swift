import Foundation

/// Цены из `pricing.json` — R-20.
public struct Pricing: Codable, Sendable {
    public struct ModelPrice: Codable, Sendable {
        public var prefix: String
        public var provider: String
        public var input: Double
        public var output: Double
        public var cachedInput: Double
        public var offPeakMultiplier: Double?
    }

    public struct PeakWindow: Codable, Sendable {
        /// Дни недели по `Calendar` (1 — воскресенье … 7 — суббота).
        public var weekdays: [Int]
        public var ranges: [[String]]
    }

    public var models: [ModelPrice]
    public var deepseekPeakUTC: PeakWindow

    /// Пустые цены (если pricing.json не найден — всё считается $0).
    public static let empty = Pricing(models: [], deepseekPeakUTC: PeakWindow(weekdays: [], ranges: []))

    public init(models: [ModelPrice], deepseekPeakUTC: PeakWindow) {
        self.models = models
        self.deepseekPeakUTC = deepseekPeakUTC
    }

    public static func load(_ url: URL) throws -> Pricing {
        try JSONDecoder().decode(Pricing.self, from: Data(contentsOf: url))
    }

    public func price(for model: String) -> ModelPrice? {
        models.filter { model.hasPrefix($0.prefix) }.max { $0.prefix.count < $1.prefix.count }
    }

    /// Пиковые часы DeepSeek (UTC): будни 01:00–04:00 и 06:00–10:00.
    public func isDeepSeekPeak(_ date: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.weekday, .hour, .minute], from: date)
        guard let wd = c.weekday, deepseekPeakUTC.weekdays.contains(wd) else { return false }
        let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        func m(_ s: String) -> Int {
            let p = s.split(separator: ":").compactMap { Int($0) }
            return (p.first ?? 0) * 60 + (p.count > 1 ? p[1] : 0)
        }
        return deepseekPeakUTC.ranges.contains { $0.count == 2 && minutes >= m($0[0]) && minutes < m($0[1]) }
    }

    /// Стоимость запроса, USD. Gemini на бесплатном ключе — $0 (R-20).
    public func cost(provider: ProviderID, model: String, usage: TokenUsage, at date: Date, geminiFreeTier: Bool) -> Double {
        if provider == .gemini && geminiFreeTier { return 0 }
        guard let p = price(for: model) else { return 0 }
        var multiplier = 1.0
        if provider == .deepseek, let off = p.offPeakMultiplier, !isDeepSeekPeak(date) { multiplier = off }
        let uncached = max(0, usage.input - (provider == .deepseek ? usage.cachedInput : 0))
        let cachedCost = Double(usage.cachedInput) * p.cachedInput
        return (Double(uncached) * p.input + Double(usage.output) * p.output + cachedCost) / 1_000_000 * multiplier
    }
}

/// Учёт расхода — R-20, R-18 Budget, строка статуса R-15. Счётчики дня и месяца хранятся в `usage.json`.
public final class UsageMeter: @unchecked Sendable {
    public struct State: Codable, Equatable, Sendable {
        public var day = ""
        public var month = ""
        public var dayCost = 0.0
        public var monthCost = 0.0
        /// Расход месяца только на платных провайдерах (для лимита).
        public var monthPaidCost = 0.0
        public var dayRequests: [String: Int] = [:]
        /// 429 у провайдера сегодня (строка статуса «Gemini: limit»).
        public var dayLimited: [String: Bool] = [:]
    }

    private let url: URL?
    private let pricing: Pricing
    private let lock = NSLock()
    public private(set) var state: State
    private let now: () -> Date

    public init(pricing: Pricing, storage: URL?, now: @escaping () -> Date = Date.init) {
        self.pricing = pricing
        self.url = storage
        self.now = now
        if let url = storage, let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(State.self, from: data) {
            state = s
        } else {
            state = State()
        }
        rollover()
    }

    static func keys(_ date: Date) -> (String, String) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let day = f.string(from: date)
        return (day, String(day.prefix(7)))
    }

    private func rollover() {
        let (day, month) = Self.keys(now())
        if state.month != month {
            state.month = month
            state.monthCost = 0
            state.monthPaidCost = 0
        }
        if state.day != day {
            state.day = day
            state.dayCost = 0
            state.dayRequests = [:]
            state.dayLimited = [:]
        }
    }

    /// Записать ответ провайдера. Возвращает true, если месячный лимит платных провайдеров достигнут.
    @discardableResult
    public func record(provider: ProviderID, model: String, usage: TokenUsage, settings: AppSettings) -> Bool {
        lock.lock()
        defer { lock.unlock(); save() }
        rollover()
        let cost = pricing.cost(provider: provider, model: model, usage: usage, at: now(), geminiFreeTier: settings.geminiFreeTier)
        state.dayCost += cost
        state.monthCost += cost
        if ChainFactory.isPaid(provider, settings: settings) { state.monthPaidCost += cost }
        state.dayRequests[provider.rawValue, default: 0] += 1
        return settings.monthlyBudgetUSD > 0 && state.monthPaidCost >= settings.monthlyBudgetUSD
    }

    public func recordError(provider: ProviderID, error: LLMError) {
        guard case .http(429, _) = error else { return }
        lock.lock()
        rollover()
        state.dayLimited[provider.rawValue] = true
        lock.unlock()
        save()
    }

    /// «Today: $0.03 · Gemini: 41 req» или «… · Gemini: limit» (R-15, A-4).
    public var statusLine: String {
        lock.lock()
        defer { lock.unlock() }
        rollover()
        let gemini = state.dayLimited[ProviderID.gemini.rawValue] == true ? "Gemini: limit" : "Gemini: \(state.dayRequests[ProviderID.gemini.rawValue] ?? 0) req"
        return String(format: "Today: $%.2f · %@", state.dayCost, gemini)
    }

    private func save() {
        guard let url else { return }
        let snapshot = lock.withLock { state }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
    }
}
