import Foundation
import Yams

/// Откуда ответ карточки (COPILOT-08 R-07, R-08).
public enum AnswerStatus: String, Codable, Sendable, CaseIterable {
    /// Ответа ещё нет: вопрос ждёт черновика.
    case none
    /// Ответ владельца — подготовка его никогда не перезаписывает.
    case own
    /// Черновик модели, ещё не просмотрен владельцем.
    case draft
    /// Черновик, подтверждённый владельцем.
    case approved

    public var title: String {
        switch self {
        case .none: L10n.t("нет ответа")
        case .own: L10n.t("ваш")
        case .draft: L10n.t("черновик")
        case .approved: L10n.t("подтверждён")
        }
    }
}

/// Карточка базы — R-06; статус ответа и подготовленные формулировки — COPILOT-08.
/// `questions[0]` — формулировка владельца, остальные — его или подготовленные моделью (uk/ru/en).
public struct BankCard: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var questions: [String]
    public var answer: String
    public var tags: [String]
    public var status: AnswerStatus
    /// Формулировки на трёх языках уже подготовлены (R-08): «Подготовить» их не повторяет.
    public var prepared: Bool

    public init(id: String, questions: [String], answer: String, tags: [String] = [], status: AnswerStatus? = nil,
                prepared: Bool = false) {
        self.id = id
        self.questions = questions
        self.answer = answer
        self.tags = tags
        self.status = status ?? (answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .none : .own)
        self.prepared = prepared
    }

    /// Есть ответ, на который можно опереться (свой, черновик или подтверждённый).
    public var hasAnswer: Bool { !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Чипы S/T/A/R (R-16).
    public var isSTAR: Bool { tags.contains { $0.uppercased() == "STAR" } }
}

/// Ошибка разбора `questions.yaml` с номером строки — для сообщения «База вопросов: ошибка в строке N» (S-10).
public struct QuestionBankError: Error, Equatable, CustomStringConvertible {
    public var line: Int?
    public var message: String

    public var description: String {
        if let line { return L10n.f("База вопросов: ошибка в строке %lld: %@", line, message) }
        return L10n.f("База вопросов: %@", message)
    }
}

/// Разбор и валидация `questions.yaml`: уникальный id `[a-z0-9-]`, ≥ 1 вопрос, непустой ответ (R-06).
public enum QuestionBankParser {
    public static func parse(_ yaml: String) throws -> [BankCard] {
        let node: Node?
        do {
            node = try Yams.compose(yaml: yaml)
        } catch let error as YamlError {
            throw QuestionBankError(line: Self.line(of: error), message: Self.short(error))
        }
        guard let node else { return [] }
        guard let items = node.sequence else {
            throw QuestionBankError(line: node.mark?.line ?? 1, message: L10n.t("ожидается список карточек (- id: …)"))
        }
        var cards: [BankCard] = []
        var seen: [String: Int] = [:]
        for item in items {
            let line = item.mark?.line ?? 0 // Yams: строки с 1
            guard let map = item.mapping else {
                throw QuestionBankError(line: line, message: L10n.t("карточка должна быть словарём с полями id, questions, answer"))
            }
            guard let id = map["id"]?.string?.trimmingCharacters(in: .whitespaces), !id.isEmpty else {
                throw QuestionBankError(line: line, message: L10n.t("нет поля id"))
            }
            guard id.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil else {
                throw QuestionBankError(line: line, message: L10n.f("id «%@» — только строчные латинские буквы, цифры и дефис", "\(id)"))
            }
            if let first = seen[id] {
                throw QuestionBankError(line: line, message: L10n.f("повтор id «%@» (первое в строке %@)", "\(id)", "\(first)"))
            }
            seen[id] = line
            let questions: [String]
            if let seq = map["questions"]?.sequence {
                questions = seq.compactMap { $0.string?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            } else if let single = map["questions"]?.string {
                questions = [single.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }
            } else {
                questions = []
            }
            guard !questions.isEmpty else {
                throw QuestionBankError(line: line, message: L10n.f("в карточке «%@» нет ни одного вопроса", "\(id)"))
            }
            // COPILOT-08 R-07: вопрос без ответа — правильная карточка (ждёт черновика), в поиск она не идёт.
            let answer = (map["answer"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let tags = map["tags"]?.sequence?.compactMap(\.string) ?? []
            let status = map["status"]?.string.flatMap(AnswerStatus.init(rawValue:))
            let prepared = map["prepared"]?.bool ?? false
            var card = BankCard(id: id, questions: questions, answer: answer, tags: tags, status: status, prepared: prepared)
            if !card.hasAnswer { card.status = .none } else if card.status == .none { card.status = .own }
            cards.append(card)
        }
        return cards
    }

    public static func load(_ url: URL) throws -> [BankCard] {
        let text: String
        do { text = try String(contentsOf: url, encoding: .utf8) } catch {
            throw QuestionBankError(line: nil, message: L10n.f("не удалось прочитать %@: %@", "\(url.lastPathComponent)", "\(error.localizedDescription)"))
        }
        return try parse(text)
    }

    static func line(of error: YamlError) -> Int? {
        switch error {
        case .scanner(_, _, let mark, _), .parser(_, _, let mark, _), .composer(_, _, let mark, _):
            return mark.line
        default:
            return nil
        }
    }

    static func short(_ error: YamlError) -> String {
        switch error {
        case .scanner(_, let problem, _, _), .parser(_, let problem, _, _), .composer(_, let problem, _, _):
            return problem
        default:
            return "\(error)"
        }
    }
}

/// Запись `questions.yaml` (COPILOT-08 R-07): формат тот же, что читает `QuestionBankParser`; ответы — блоком `|`.
public enum QuestionBankWriter {
    public static let header = "# Вопросы профиля (COPILOT-08). Правится в окне «Профиль» → «Вопросы» или здесь.\n"
        + "# status: own — ваш ответ, draft — черновик модели, approved — подтверждённый черновик, none — без ответа.\n"

    public static func yaml(_ cards: [BankCard]) -> String {
        guard !cards.isEmpty else { return header + "[]\n" }
        var out = header
        for c in cards {
            out += "- id: \(c.id)\n"
            out += "  status: \(c.status.rawValue)\n"
            if c.prepared { out += "  prepared: true\n" }
            if !c.tags.isEmpty { out += "  tags: [\(c.tags.map(quote).joined(separator: ", "))]\n" }
            out += "  questions:\n"
            for q in c.questions { out += "    - \(quote(q))\n" }
            let answer = c.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            if answer.isEmpty {
                out += "  answer: \"\"\n"
            } else {
                out += "  answer: |\n"
                for line in answer.components(separatedBy: "\n") { out += line.isEmpty ? "\n" : "    \(line)\n" }
            }
            out += "\n"
        }
        return out
    }

    /// Строка YAML в двойных кавычках (экранирование совместимо с JSON).
    static func quote(_ s: String) -> String {
        let one = s.replacingOccurrences(of: "\n", with: " ")
        let data = (try? JSONSerialization.data(withJSONObject: [one], options: [.withoutEscapingSlashes])) ?? Data()
        let json = String(decoding: data, as: UTF8.self)
        return String(json.dropFirst().dropLast())
    }

    /// Свободный id карточки: q-1, q-2…
    public static func nextID(_ cards: [BankCard]) -> String {
        let used = Set(cards.map(\.id))
        var n = cards.count + 1
        while used.contains("q-\(n)") { n += 1 }
        return "q-\(n)"
    }
}

/// Подсказка для распознавания речи из базы: формулировки вопросов на нужном языке (по алфавиту письма),
/// не длиннее `limit` символов. Термины и имена из базы чаще распознаются верно.
public enum RecognitionVocabulary {
    public static func prompt(cards: [BankCard], language: String, limit: Int = 400) -> String {
        func lang(_ q: String) -> String {
            if q.range(of: "[іїєґІЇЄҐ]", options: .regularExpression) != nil { return "uk" }
            if q.range(of: "[а-яА-ЯёЁ]", options: .regularExpression) != nil { return "ru" }
            return "en"
        }
        var out = ""
        for card in cards {
            for q in card.questions where lang(q) == language {
                let next = out.isEmpty ? q : out + " " + q
                if next.count > limit { return out }
                out = next
                break // по одной формулировке на карточку — шире словарь
            }
        }
        return out
    }
}
