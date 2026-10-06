import Foundation
import Yams

/// Карточка базы — R-06.
public struct BankCard: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var questions: [String]
    public var answer: String
    public var tags: [String]

    public init(id: String, questions: [String], answer: String, tags: [String] = []) {
        self.id = id
        self.questions = questions
        self.answer = answer
        self.tags = tags
    }

    /// Чипы S/T/A/R (R-16).
    public var isSTAR: Bool { tags.contains { $0.uppercased() == "STAR" } }
}

/// Ошибка разбора `questions.yaml` с номером строки — для сообщения «Question bank: ошибка в строке N» (S-10).
public struct QuestionBankError: Error, Equatable, CustomStringConvertible {
    public var line: Int?
    public var message: String

    public var description: String {
        if let line { return "Question bank: ошибка в строке \(line): \(message)" }
        return "Question bank: \(message)"
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
            throw QuestionBankError(line: node.mark?.line ?? 1, message: "ожидается список карточек (- id: …)")
        }
        var cards: [BankCard] = []
        var seen: [String: Int] = [:]
        for item in items {
            let line = item.mark?.line ?? 0 // Yams: строки с 1
            guard let map = item.mapping else {
                throw QuestionBankError(line: line, message: "карточка должна быть словарём с полями id, questions, answer")
            }
            guard let id = map["id"]?.string?.trimmingCharacters(in: .whitespaces), !id.isEmpty else {
                throw QuestionBankError(line: line, message: "нет поля id")
            }
            guard id.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil else {
                throw QuestionBankError(line: line, message: "id «\(id)» — только строчные латинские буквы, цифры и дефис")
            }
            if let first = seen[id] {
                throw QuestionBankError(line: line, message: "повтор id «\(id)» (первое в строке \(first))")
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
                throw QuestionBankError(line: line, message: "в карточке «\(id)» нет ни одного вопроса")
            }
            let answer = (map["answer"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else {
                throw QuestionBankError(line: line, message: "в карточке «\(id)» пустой ответ")
            }
            let tags = map["tags"]?.sequence?.compactMap(\.string) ?? []
            cards.append(BankCard(id: id, questions: questions, answer: answer, tags: tags))
        }
        return cards
    }

    public static func load(_ url: URL) throws -> [BankCard] {
        let text: String
        do { text = try String(contentsOf: url, encoding: .utf8) } catch {
            throw QuestionBankError(line: nil, message: "не удалось прочитать \(url.lastPathComponent): \(error.localizedDescription)")
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
