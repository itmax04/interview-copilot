import Foundation

/// Настройки ответа — COPILOT-09 R-12 (решение владельца Q6): формат, длина, тон. Меняют форму ответа, не факты.
/// Стандарт (сценарий + пункты, сбалансированный, нейтральный) дает ровно прежнее правило промпта.
/// Инструкции владельца важнее (08/R-04): блок `<owner_instructions>` идет после и прямо это говорит.
public struct AnswerStyle: Codable, Equatable, Hashable, Sendable {
    public enum Format: String, Codable, CaseIterable, Sendable, Identifiable {
        /// Первая строка жирным — суть, ниже пункты.
        case scriptAndBullets
        case bullets
        /// Сплошной текст, как произносить вслух.
        case script

        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .scriptAndBullets: L10n.t("Суть + пункты")
            case .bullets: L10n.t("Только пункты")
            case .script: L10n.t("Сплошной текст")
            }
        }
        /// Для переключателя (узкая колонка).
        public var shortTitle: String {
            switch self {
            case .scriptAndBullets: L10n.t("Суть + пункты")
            case .bullets: L10n.t("Пункты")
            case .script: L10n.t("Текст")
            }
        }
    }

    public enum Length: String, Codable, CaseIterable, Sendable, Identifiable {
        case short, balanced, detailed

        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .short: L10n.t("Короткий")
            case .balanced: L10n.t("Сбалансированный")
            case .detailed: L10n.t("Подробный")
            }
        }
        /// Предел слов в правиле промпта.
        public var maxWords: Int {
            switch self {
            case .short: 40
            case .balanced: 80
            case .detailed: 150
            }
        }
        var bulletRange: String {
            switch self {
            case .short: "2–3"
            case .balanced: "2–5"
            case .detailed: "3–7"
            }
        }
    }

    public enum Tone: String, Codable, CaseIterable, Sendable, Identifiable {
        case formal, neutral, friendly

        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .formal: L10n.t("Формальный")
            case .neutral: L10n.t("Нейтральный")
            case .friendly: L10n.t("Дружелюбный")
            }
        }
    }

    public var format: Format = .scriptAndBullets
    public var length: Length = .balanced
    public var tone: Tone = .neutral

    public init(format: Format = .scriptAndBullets, length: Length = .balanced, tone: Tone = .neutral) {
        self.format = format
        self.length = length
        self.tone = tone
    }

    public static let standard = AnswerStyle()

    /// «Суть + пункты · сбалансированный · нейтральный».
    public var summary: String { "\(format.title) · \(length.title.lowercased()) · \(tone.title.lowercased())" }

    /// Правило формата для системной части. `subject` — «the core answer» (собеседование) или «the core of what to say»
    /// (обычный звонок). Стандарт — дословно прежнее правило: кэш промпта и проверенное поведение не меняются.
    public func formatRule(subject: String = "the core answer") -> String {
        let words = length.maxWords
        var rule: String
        switch format {
        case .scriptAndBullets:
            rule = "- First line: \(subject) in one short sentence in **bold**, so the speaker can start at once. "
                + "Then \(length.bulletRange) short bullet points with details, at most \(words) words in total. No preamble, no headings."
            if self == .standard {
                rule = subject == "the core answer"
                    ? "- First line: the core answer in one short sentence in **bold**, so the candidate can start speaking at once. "
                        + "Then 2–5 short bullet points with details, at most 80 words in total. No preamble, no headings."
                    : "- First line: \(subject) in one short sentence in **bold**. Then 2–5 short bullet points with details, "
                        + "arguments or numbers, at most 80 words in total. No preamble, no headings."
            }
        case .bullets:
            rule = "- Only \(length.bulletRange) short bullet points, each line starting with \"- \"; the first bullet is \(subject) "
                + "in **bold**. At most \(words) words in total. No paragraph of prose, no preamble, no headings."
        case .script:
            rule = "- A natural spoken script in plain sentences, exactly as it would be said out loud: \(subject) first, then "
                + "the details. No bullet points, no bold, no headings, no lists. At most \(words) words in total."
        }
        switch tone {
        case .neutral: break
        case .formal: rule += "\n- Tone: formal and precise, business vocabulary, no slang, jokes or exclamations."
        case .friendly: rule += "\n- Tone: warm, friendly and conversational, still professional; simple words, a natural spoken rhythm."
        }
        return rule
    }

    /// Токенов на ответ: подробному не хватает прежних 400.
    public var maxTokens: Int { length == .detailed ? 800 : 400 }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = (try? c.decodeIfPresent(Format.self, forKey: .format)) ?? .scriptAndBullets
        length = (try? c.decodeIfPresent(Length.self, forKey: .length)) ?? .balanced
        tone = (try? c.decodeIfPresent(Tone.self, forKey: .tone)) ?? .neutral
    }
}

/// Пример вопроса для живого предпросмотра (R-12): ответ модели на него по активному профилю.
public enum StylePreviewQuestion: String, CaseIterable, Sendable, Identifiable {
    case about, behavioral, technical

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .about: L10n.t("О себе")
        case .behavioral: L10n.t("Поведенческий")
        case .technical: L10n.t("Технический")
        }
    }

    /// Текст вопроса на языке ответа (uk / ru / en; другой — английский).
    public func text(language: String) -> String {
        switch (self, language) {
        case (.about, "uk"): "Розкажіть трохи про себе."
        case (.about, "ru"): "Расскажите немного о себе."
        case (.about, _): "Tell me a bit about yourself."
        case (.behavioral, "uk"): "Розкажіть про конфлікт у команді і як ви його вирішили."
        case (.behavioral, "ru"): "Расскажите о конфликте в команде и как вы его решили."
        case (.behavioral, _): "Tell me about a conflict in your team and how you resolved it."
        case (.technical, "uk"): "Як ви обробляєте помилки в мережевому шарі застосунку?"
        case (.technical, "ru"): "Как вы обрабатываете ошибки в сетевом слое приложения?"
        case (.technical, _): "How do you handle errors in the app's networking layer?"
        }
    }

    /// Вопрос для обычного звонка (Regular): «что сказать» по теме, а не собеседование.
    public func regularText(language: String) -> String {
        switch (self, language) {
        case (.about, "uk"): "Розкажіть коротко, чим ви займаєтеся."
        case (.about, "ru"): "Расскажите коротко, чем вы занимаетесь."
        case (.about, _): "Briefly, what do you do?"
        case (.behavioral, "uk"): "Ми не встигаємо до дедлайну. Що пропонуєте?"
        case (.behavioral, "ru"): "Мы не успеваем к дедлайну. Что предлагаете?"
        case (.behavioral, _): "We're going to miss the deadline. What do you suggest?"
        case (.technical, "uk"): "Чому ви пропонуєте саме цей підхід до архітектури?"
        case (.technical, "ru"): "Почему вы предлагаете именно этот подход к архитектуре?"
        case (.technical, _): "Why do you propose this particular architecture?"
        }
    }
}

/// Проверки формы ответа (AC-06): тесты, живой прогон и подпись в предпросмотре («38 слов»).
public enum AnswerShape {
    /// Слова без markdown-разметки и номеров пунктов («1.», «2)»).
    public static func words(_ text: String) -> Int {
        text.split(whereSeparator: \.isNewline).reduce(0) { count, line in
            var tokens = line.replacingOccurrences(of: "**", with: "").split(whereSeparator: { $0.isWhitespace })
            if let first = tokens.first, isBullet(line), first.last == "." || first.last == ")", first.dropLast().allSatisfy(\.isNumber) {
                tokens.removeFirst()
            }
            return count + tokens.filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }.count
        }
    }

    public static func isBullet(_ line: Substring) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if ["- ", "• ", "* ", "– "].contains(where: { t.hasPrefix($0) }) { return true }
        // «1. », «2) »
        guard let first = t.first, first.isNumber else { return false }
        let rest = t.drop(while: { $0.isNumber })
        return rest.hasPrefix(". ") || rest.hasPrefix(") ")
    }

    public static func bulletCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isNewline).filter(isBullet).count
    }

    /// Непустые строки, которые не пункты (для «Только пункты»).
    public static func proseLines(_ text: String) -> Int {
        text.split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !isBullet($0) }
            .count
    }
}
