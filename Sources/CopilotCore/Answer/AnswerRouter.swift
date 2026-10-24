import Foundation

/// Что делать с ходом — R-08, S-01…S-03.
public enum AnswerDecision: Equatable, Sendable {
    /// Показать карточку базы (S-01).
    case bankCard(CardScore)
    /// «Нет в базе» + топ-3, без запроса к модели (S-02).
    case noMatch(top: [CardScore])
    /// Генерация: `base` — найденная карточка как основа ответа (режим «Generate every answer»), `top` — контекст (R-11).
    case generate(base: BankCard?, top: [CardScore])
}

public enum AnswerRouter {
    /// `modelsAvailable` — есть ли хоть один провайдер с ключом; без них действует S-02 (S-04).
    /// `useProfile == false` — «Без профиля» (R-40): база — часть профиля и не используется, модель отвечает на каждый ход
    /// независимо от режима.
    public static func decide(mode: AnswerMode, match: BankMatch, modelsAvailable: Bool, useProfile: Bool = true) -> AnswerDecision {
        guard useProfile else {
            return modelsAvailable ? .generate(base: nil, top: []) : .noMatch(top: [])
        }
        switch mode {
        case .bankOnly:
            if let m = match.matched { return .bankCard(m) }
            return .noMatch(top: match.top)
        case .bankAndHint:
            // COPILOT-08 R-09 (решение владельца Q6): похожий вопрос с ответом владельца — модель подстраивает этот ответ
            // под формулировку и язык; без моделей — карточка дословно.
            guard modelsAvailable else {
                if let m = match.matched { return .bankCard(m) }
                return .noMatch(top: match.top)
            }
            return .generate(base: match.matched?.card, top: match.top)
        case .generateAlways:
            guard modelsAvailable else {
                if let m = match.matched { return .bankCard(m) }
                return .noMatch(top: match.top)
            }
            return .generate(base: match.matched?.card, top: match.top)
        }
    }
}
