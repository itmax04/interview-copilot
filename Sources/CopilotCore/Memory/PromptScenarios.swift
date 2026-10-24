import Foundation

/// Сценарии живой проверки памяти и правил промпта на настоящей модели (COPILOT-07, `--smoke-memory`).
/// Данные синтетические; проверка — по тексту ответа, без участия человека.
public enum PromptScenarios {
    public struct Scenario: Sendable {
        public var name: String
        public var question: String
        public var language: String
        public var memory: MemoryContext
        /// Профиль и общие инструкции (COPILOT-08); nil — «Без профиля».
        public var profile: Profile? = nil
        public var general = ""
        /// nil — PASS, иначе причина FAIL.
        public var check: @Sendable (String) -> String?

        public init(name: String, question: String, language: String, memory: MemoryContext, profile: Profile? = nil,
                    general: String = "", check: @escaping @Sendable (String) -> String?) {
            self.name = name
            self.question = question
            self.language = language
            self.memory = memory
            self.profile = profile
            self.general = general
            self.check = check
        }
    }

    /// Синтетический профиль для сценариев COPILOT-08.
    static let sampleProfile = Profile(name: "Тест", resume: """
        Олексій Коваль — Senior iOS Developer, 7 років досвіду.
        ФінБанк (2021–2026): мобільний банк, 1,2 млн користувачів, команда з 6 iOS-розробників, переписав платежі на SwiftUI.
        Технології: Swift, SwiftUI, Combine, RabbitMQ, PostgreSQL.
        """)

    static func bullets(_ text: String) -> Int {
        text.split(whereSeparator: \.isNewline).filter {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("- ") || t.hasPrefix("• ") || t.hasPrefix("* ")
        }.count
    }

    /// Первая строка ответа без разметки, в нижнем регистре.
    public static func firstLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return line.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Ответ подтверждает то, чего кандидат не говорил: «Так, …», «Да, …», «Yes, …» или «как я говорил».
    public static func confirmsPremise(_ text: String) -> Bool {
        let first = firstLine(text)
        let starts = ["так,", "так.", "так —", "так ", "да,", "да.", "да —", "yes,", "yes.", "yes "]
        // «Так як…» — «так как», не согласие.
        if starts.contains(where: { first.hasPrefix($0) }), !first.hasPrefix("так як") { return true }
        let lower = text.lowercased()
        let claims = ["як я казав", "як я вже казав", "як я згадував", "як я вже згадував", "як я говорив", "как я говорил",
                      "как я уже говорил", "как я упоминал", "как я уже упоминал", "as i said", "as i mentioned", "as i've mentioned"]
        return claims.contains { lower.contains($0) }
    }

    private static func noConfirmation(_ text: String) -> String? {
        confirmsPremise(text) ? "подтверждает несказанное: «\(firstLine(text))»" : nil
    }

    public static let all: [Scenario] = [
        // Живой тест COPILOT-06 (распознанный текст как есть): Kafka только в показанной подсказке прошлого хода.
        Scenario(name: "ловушка: Kafka только в показанной подсказке", question: "Ви чи ви згадували, що працювали з Кавкой?",
                 language: "uk",
                 memory: MemoryContext(recent: [
                    .init(minutesAgo: 1, question: "Чи готові ви до переїзду?", answer: "",
                          shownHint: "Так, я готовий до переїзду, якщо це необхідно для проєкту."),
                    .init(minutesAgo: 1, question: "Повернемося до вашого останнього проекту, який результат ви отримали в цифрах?",
                          answer: "", shownHint: "Підвищили конверсію з 2,1 % до 3,8 %; скоротили час обробки замовлення з 12 до 4 хв."),
                    .init(minutesAgo: 0, question: "Ви питання такі визгадували, що працювалася з Кавкарю?", answer: "",
                          shownHint: "Я працював з широким стеком технологій; Java Spring Boot для бекенду; Kafka для обробки подій у реальному часі."),
                 ], backReference: true),
                 check: noConfirmation),
        Scenario(name: "ловушка: истории нет (uk)", question: "Ви згадували, що працювали з Kafka, — розкажіть детальніше.",
                 language: "uk", memory: MemoryContext(backReference: true), check: noConfirmation),
        Scenario(name: "ловушка: истории нет (ru)", question: "Вы упоминали, что работали с Kafka, — расскажите подробнее.",
                 language: "ru", memory: MemoryContext(backReference: true), check: noConfirmation),
        Scenario(name: "возврат к записанному ответу", question: "Ви згадували RabbitMQ — скільки повідомлень на день він обробляв?",
                 language: "uk",
                 memory: MemoryContext(recent: [
                    .init(minutesAgo: 6, question: "Яку чергу повідомлень ви використовували?",
                          answer: "Ми використовували RabbitMQ, обробляли близько двох мільйонів повідомлень на день."),
                    .init(minutesAgo: 4, question: "Як ви тестуєте?", answer: "Юніт-тести і контрактні тести."),
                 ], backReference: true),
                 check: { text in
                     let t = text.lowercased()
                     let keepsNumber = (t.contains("2") || t.contains("дв")) && (t.contains("млн") || t.contains("мільйон"))
                     return keepsNumber ? nil : "не держит цифру из ответа (2 млн): «\(firstLine(text))»"
                 }),
        Scenario(name: "зарплата без профиля — рыночная вилка", question: "Які у вас зарплатні очікування?", language: "uk",
                 memory: MemoryContext(), check: { text in
                     let t = text.lowercased()
                     return t.contains("$") || t.contains("usd") || t.contains("дол") ? nil : "нет суммы в USD: «\(firstLine(text))»"
                 }),
        Scenario(name: "обрывок — не вопрос", question: "Є таке питання.", language: "uk", memory: MemoryContext(),
                 check: { text in PromptBuilder.isNoAnswer(text) ? nil : "ответ вместо «—»: «\(firstLine(text))»" }),
        // COPILOT-08: инструкции владельца и факты резюме.
        Scenario(name: "инструкция: без списков, 2 предложения", question: "Розкажіть про себе.", language: "uk", memory: MemoryContext(),
                 profile: { var p = sampleProfile; p.instructions = "Відповідай двома реченнями, без списків і без жирного шрифту."; return p }(),
                 check: { text in
                     bullets(text) == 0 && !text.contains("**") ? nil : "есть список или жирный: «\(firstLine(text))»"
                 }),
        Scenario(name: "инструкция: не упоминать Kafka", question: "Які брокери повідомлень ви використовували?", language: "uk",
                 memory: MemoryContext(), profile: sampleProfile,
                 general: "Ніколи не згадуй Kafka — я з нею не працював. Говори про RabbitMQ.",
                 check: { text in
                     let t = text.lowercased()
                     if t.contains("kafka") || t.contains("кафк") { return "упомянута Kafka: «\(firstLine(text))»" }
                     return t.contains("rabbitmq") ? nil : "нет RabbitMQ: «\(firstLine(text))»"
                 }),
        Scenario(name: "факт из резюме", question: "Скільки користувачів було у вашому останньому проєкті?", language: "uk",
                 memory: MemoryContext(), profile: sampleProfile,
                 check: { text in
                     let t = text.lowercased()
                     return (t.contains("1,2") || t.contains("1.2")) && (t.contains("млн") || t.contains("мільйон") || t.contains("million")) ? nil : "нет 1,2 млн из резюме: «\(firstLine(text))»"
                 }),
        Scenario(name: "инструкция: язык ответа", question: "Чому ви хочете змінити роботу?", language: "uk", memory: MemoryContext(),
                 profile: sampleProfile, general: "Always answer in English, whatever the interview language.",
                 check: { text in
                     let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
                     let latin = letters.filter { $0.isASCII }.count
                     return letters.isEmpty || Double(latin) / Double(letters.count) > 0.8 ? nil : "не по-английски: «\(firstLine(text))»"
                 }),
    ]

    /// Запрос подсказки сценария — как в приложении в режиме «Без профиля».
    public static func request(_ s: Scenario) -> LLMRequest {
        PromptBuilder.hintRequest(question: s.question, transcript: [], cards: [], baseCard: nil, profile: s.profile, redactPII: true,
                                  answerLanguage: s.language, memory: s.memory, generalInstructions: s.general)
    }
}
