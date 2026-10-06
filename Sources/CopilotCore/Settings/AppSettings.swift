import Foundation

/// Источник звука — R-01.
public enum AudioSourceSetting: Codable, Equatable, Sendable {
    /// Первое запущенное из zoom.us → Google Chrome → Telegram.
    case auto
    /// Конкретное приложение.
    case app(bundleID: String, name: String)
    /// Весь системный звук (кроме самого помощника).
    case allSystem
}

public enum PanelFontSize: String, Codable, CaseIterable, Sendable {
    case small = "S", medium = "M", large = "L"

    public var pointSize: Double {
        switch self {
        case .small: 12
        case .medium: 14
        case .large: 16
        }
    }
}

/// ID моделей провайдеров — R-09 (редактируются в Settings → Models). Проверяются по спискам моделей на P-07.
public struct ModelIDs: Codable, Equatable, Sendable {
    public var gemini = "gemini-3.8-flash"
    public var deepseek = "deepseek-flash"
    public var anthropic = "claude-sonnet-5-5"

    public init() {}

    /// ID для запроса: без пробелов; пустое поле в настройках означает ID по умолчанию.
    public func effective(_ provider: ProviderID) -> String {
        let trimmed = self[provider].trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ModelIDs()[provider] : trimmed
    }

    public subscript(provider: ProviderID) -> String {
        get {
            switch provider {
            case .gemini: gemini
            case .deepseek: deepseek
            case .anthropic: anthropic
            }
        }
        set {
            switch provider {
            case .gemini: gemini = newValue
            case .deepseek: deepseek = newValue
            case .anthropic: anthropic = newValue
            }
        }
    }
}

/// Все настройки приложения — R-18. Значения по умолчанию взяты из spec.md.
public struct AppSettings: Codable, Equatable, Sendable {
    // Models
    public var modelIDs = ModelIDs()
    public var chain: [ProviderID] = [.gemini, .deepseek, .anthropic]
    /// Сильная модель для ⌃⌥C и скриншотов (S-05, S-06).
    public var strongProvider: ProviderID = .anthropic
    /// Таймаут первого токена, с (R-09: 4 с).
    public var firstTokenTimeout: Double = 4

    // Audio
    /// Файл модели whisper в `…/InterviewCopilot/models/` (ADR-0001 п. 5: small по замерам P-04).
    public var whisperModel = AppSettings.defaultWhisperModel
    public var audioSource: AudioSourceSetting = .auto
    public var language: RecognitionLanguage = .auto
    /// Порог паузы T, мс (R-05: 700, диапазон 400–1500).
    public var pauseThresholdMs: Int = 700

    // Answer / Bank
    public var mode: AnswerMode = .bankAndHint
    /// Порог совпадения с карточкой (R-07: 0,85).
    public var bankThreshold: Double = 0.85

    // Privacy
    public var piiFilterEnabled = true
    public var historyRetentionDays = 30

    // Panel
    public var panelOpacity: Double = 0.92
    public var panelFontSize: PanelFontSize = .medium
    public var panelWidth: Double = 380

    // Budget
    public var monthlyBudgetUSD: Double = 5
    /// Ключ Gemini бесплатного тарифа — стоимость $0 (R-20).
    public var geminiFreeTier = true
    /// Платные провайдеры выключены после достижения лимита, пока владелец не подтвердит (R-18 Budget).
    public var paidProvidersSuspended = false

    public init() {}

    public static let defaultWhisperModel = "ggml-small-q5_1.bin"
    public static let pauseThresholdRange = 400...1500
    public static let bankThresholdRange = 0.5...0.99
    public static let firstTokenTimeoutRange = 1.0...15.0
    public static let retentionRange = 1...365
    public static let panelOpacityRange = 0.7...1.0
    public static let panelWidthRange = 300.0...520.0
    public static let budgetRange = 0.0...1000.0

    /// Значения в допустимых диапазонах; цепочка без повторов и со всеми провайдерами.
    public func normalized() -> AppSettings {
        var s = self
        s.firstTokenTimeout = s.firstTokenTimeout.clamped(to: Self.firstTokenTimeoutRange)
        s.pauseThresholdMs = s.pauseThresholdMs.clamped(to: Self.pauseThresholdRange)
        s.bankThreshold = s.bankThreshold.clamped(to: Self.bankThresholdRange)
        s.historyRetentionDays = s.historyRetentionDays.clamped(to: Self.retentionRange)
        s.panelOpacity = s.panelOpacity.clamped(to: Self.panelOpacityRange)
        s.panelWidth = s.panelWidth.clamped(to: Self.panelWidthRange)
        s.monthlyBudgetUSD = s.monthlyBudgetUSD.clamped(to: Self.budgetRange)
        var seen = Set<ProviderID>()
        s.chain = s.chain.filter { seen.insert($0).inserted }
        s.chain += ProviderID.allCases.filter { !seen.contains($0) }
        return s
    }

    // Отсутствующие в сохранённом JSON поля получают значения по умолчанию: настройки переживают обновления приложения.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        modelIDs = v(.modelIDs, d.modelIDs)
        chain = v(.chain, d.chain)
        strongProvider = v(.strongProvider, d.strongProvider)
        firstTokenTimeout = v(.firstTokenTimeout, d.firstTokenTimeout)
        whisperModel = v(.whisperModel, d.whisperModel)
        audioSource = v(.audioSource, d.audioSource)
        language = v(.language, d.language)
        pauseThresholdMs = v(.pauseThresholdMs, d.pauseThresholdMs)
        mode = v(.mode, d.mode)
        bankThreshold = v(.bankThreshold, d.bankThreshold)
        piiFilterEnabled = v(.piiFilterEnabled, d.piiFilterEnabled)
        historyRetentionDays = v(.historyRetentionDays, d.historyRetentionDays)
        panelOpacity = v(.panelOpacity, d.panelOpacity)
        panelFontSize = v(.panelFontSize, d.panelFontSize)
        panelWidth = v(.panelWidth, d.panelWidth)
        monthlyBudgetUSD = v(.monthlyBudgetUSD, d.monthlyBudgetUSD)
        geminiFreeTier = v(.geminiFreeTier, d.geminiFreeTier)
        paidProvidersSuspended = v(.paidProvidersSuspended, d.paidProvidersSuspended)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
