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
        /// Найденные фрагменты материалов (COPILOT-08 R-06).
        public var materials: [MaterialHit] = []
        /// Найденная карточка с ответом владельца (COPILOT-08 R-09).
        public var base: BankCard? = nil
        /// Сессия: тип звонка и указания (COPILOT-09).
        public var session: SessionPrompt? = nil
        /// Уточнение показанного ответа (COPILOT-09 R-10): прежний ответ и указание.
        public var refine: (previous: String, instruction: String)? = nil
        /// nil — PASS, иначе причина FAIL.
        public var check: @Sendable (String) -> String?

        public init(name: String, question: String, language: String, memory: MemoryContext, profile: Profile? = nil,
                    general: String = "", materials: [MaterialHit] = [], base: BankCard? = nil, session: SessionPrompt? = nil,
                    refine: (previous: String, instruction: String)? = nil, check: @escaping @Sendable (String) -> String?) {
            self.refine = refine
            self.name = name
            self.question = question
            self.language = language
            self.memory = memory
            self.profile = profile
            self.general = general
            self.materials = materials
            self.base = base
            self.session = session
            self.check = check
        }
    }

    /// Синтетический профиль для сценариев COPILOT-08.
    public static let sampleProfile = Profile(name: "Тест", resume: """
        Олексій Коваль — Senior iOS Developer, 7 років досвіду.
        ФінБанк (2021–2026): мобільний банк, 1,2 млн користувачів, команда з 6 iOS-розробників, переписав платежі на SwiftUI.
        Технології: Swift, SwiftUI, Combine, RabbitMQ, PostgreSQL.
        """)

    /// Числа в тексте («1,2», «70», «2021») — для проверки, что модель не придумала новых. Код (```…``` и `…`) не
    /// считается: числа в примере кода — не факты о кандидате.
    public static func numbers(_ text: String) -> Set<String> {
        let prose = text.replacingOccurrences(of: #"```[\s\S]*?```"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"`[^`]*`"#, with: " ", options: .regularExpression)
        let normalized = prose.replacingOccurrences(of: ".", with: ",")
        guard let re = try? NSRegularExpression(pattern: #"\d+(?:,\d+)?"#) else { return [] }
        let ns = normalized as NSString
        return Set(re.matches(in: normalized, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) })
    }

    public static func bullets(_ text: String) -> Int {
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
        Scenario(name: "материалы: факт из конспекта", question: "Що ви робите з повідомленнями, які не вдалося обробити?",
                 language: "uk", memory: MemoryContext(), profile: sampleProfile,
                 materials: [MaterialHit(source: "system-design.md", text: "В ФинБанке RabbitMQ: около двух миллионов сообщений в день, подтверждения доставки (ack) и очередь мёртвых писем для сообщений, которые не обработались за три попытки.", score: 0.62)],
                 check: { text in
                     let t = text.lowercased()
                     let deadLetter = t.contains("dead") || t.contains("мертв") || t.contains("dlq")
                     let three = ["три", "трьох", "трёх", "three", "3"].contains { t.contains($0) }
                     return deadLetter && three ? nil : "нет очереди мёртвых писем и трёх попыток: «\(firstLine(text))»"
                 }),
        Scenario(name: "подстройка ответа владельца: другой язык, факты те же",
                 question: "Расскажите, что вы делали с платёжным модулем?", language: "ru", memory: MemoryContext(), profile: sampleProfile,
                 base: BankCard(id: "payments", questions: ["Розкажіть про роботу з платіжним модулем"],
                                answer: "Я переписав платежі на SwiftUI за 3 місяці: час оплати впав з 9 до 4 секунд, кількість помилок оплати — на 30 %."),
                 check: { text in
                     let t = text.lowercased()
                     let facts = t.contains("9") && t.contains("4") && t.contains("30")
                     let russian = !t.contains("і") && !t.contains("ї") && !t.contains("є")
                     if !facts { return "потеряны факты ответа (3 мес., 9→4 с, 30 %): «\(firstLine(text))»" }
                     return russian ? nil : "не по-русски: «\(firstLine(text))»"
                 }),
        // COPILOT-09: обычный звонок и указания на сессию.
        Scenario(name: "обычный звонок: что сказать по материалам", question: "Когда сможете прислать смету и сколько это будет стоить?",
                 language: "ru", memory: MemoryContext(), profile: Profile(name: "p"),
                 materials: [MaterialHit(source: "смета.md", text: "Смета для клиента: 3 недели работы, 12 000 $, старт с 1 ноября.", score: 0.6)],
                 session: SessionPrompt(type: .regular),
                 check: { text in
                     let t = text.lowercased()
                     if t.contains("резюме") || t.contains("собеседован") { return "звучит как собеседование: «\(firstLine(text))»" }
                     return t.contains("12") && (t.contains("недел") || t.contains("3")) ? nil : "нет цифр из материалов: «\(firstLine(text))»"
                 }),
        Scenario(name: "указание на сессию важнее профиля", question: "Розкажіть про себе.", language: "uk", memory: MemoryContext(),
                 profile: { var p = sampleProfile; p.instructions = "Відповідай українською."; return p }(),
                 session: SessionPrompt(type: .interview, instructions: "Answer only in English for this session."),
                 check: { text in
                     let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
                     let latin = letters.filter { $0.isASCII }.count
                     return letters.isEmpty || Double(latin) / Double(letters.count) > 0.8 ? nil : "не по-английски: «\(firstLine(text))»"
                 }),
        Scenario(name: "уточнение: короче", question: "Розкажіть про себе.", language: "uk", memory: MemoryContext(),
                 profile: sampleProfile, refine: (longAnswer, PromptBuilder.quickRefinements["Короче"]!),
                 check: { text in
                     let words = text.split(whereSeparator: { $0.isWhitespace }).count
                     if words > 45 { return "не короче: \(words) слов" }
                     if text.lowercased().contains("previous_answer") { return "служебный тег в ответе" }
                     return text.contains("7") || text.contains("сім") ? nil : "потерян ключевой факт (7 років): «\(firstLine(text))»"
                 }),
        Scenario(name: "уточнение: свободное указание без факта", question: "Розкажіть про себе.", language: "uk", memory: MemoryContext(),
                 profile: sampleProfile, refine: (longAnswer, "do not mention the bank's user count or rating"),
                 check: { text in
                     let t = text.lowercased()
                     if t.contains("1,2") || t.contains("4,8") || t.contains("млн") { return "указание не выполнено: «\(firstLine(text))»" }
                     return t.contains("swiftui") || t.contains("7") ? nil : "потеряны остальные факты: «\(firstLine(text))»"
                 }),
        Scenario(name: "уточнение: подробнее без выдуманных цифр", question: "Розкажіть про себе.", language: "uk", memory: MemoryContext(),
                 profile: sampleProfile, refine: (longAnswer, PromptBuilder.quickRefinements["Подробнее"]!),
                 check: { text in
                     let invented = numbers(text).subtracting(numbers(longAnswer + sampleProfile.resume))
                     return invented.isEmpty ? nil : "выдуманные цифры \(invented.sorted()): «\(firstLine(text))»"
                 }),
        Scenario(name: "уточнение: пример без выдуманного опыта", question: "Розкажіть про себе.", language: "uk", memory: MemoryContext(),
                 profile: sampleProfile, refine: (longAnswer, PromptBuilder.quickRefinements["Пример"]!),
                 check: { text in
                     let invented = numbers(text).subtracting(numbers(longAnswer + sampleProfile.resume))
                     return invented.isEmpty ? nil : "выдуманные цифры \(invented.sorted()): «\(firstLine(text))»"
                 }),
        Scenario(name: "уточнение: язык сохраняется", question: "Розкажіть про себе.", language: "uk", memory: MemoryContext(),
                 profile: sampleProfile, refine: (longAnswer, PromptBuilder.quickRefinements["Подробнее"]!),
                 check: { text in
                     let t = text.lowercased()
                     let uk = ["і", "ї", "є", "років"].contains { t.contains($0) }
                     return uk ? nil : "язык сменился: «\(firstLine(text))»"
                 }),
        // COPILOT-09 R-12, AC-06: настройки ответа меняют форму, факты — из профиля.
        Scenario(name: "стиль: короткий сплошной текст", question: "Розкажіть про себе.", language: "uk", memory: MemoryContext(),
                 profile: sampleProfile, session: SessionPrompt(style: AnswerStyle(format: .script, length: .short)),
                 check: { text in
                     let words = AnswerShape.words(text)
                     if words > 40 { return "длиннее 40 слов: \(words)" }
                     if AnswerShape.bulletCount(text) > 0 || text.contains("**") { return "есть пункты или жирный: «\(firstLine(text))»" }
                     // «7 років», «сім років», «семирічний» — один и тот же факт.
                     let t = text.lowercased()
                     return text.contains("7") || t.contains("сім") || t.contains("семи") ? nil : "потерян факт (7 років): «\(firstLine(text))»"
                 }),
        Scenario(name: "стиль: только пункты", question: "Як ви обробляєте помилки в мережевому шарі застосунку?", language: "uk",
                 memory: MemoryContext(), profile: sampleProfile, session: SessionPrompt(style: AnswerStyle(format: .bullets)),
                 check: { text in
                     let prose = AnswerShape.proseLines(text), bullets = AnswerShape.bulletCount(text)
                     return prose == 0 && bullets >= 2 ? nil : "пунктов \(bullets), строк не пунктами \(prose): «\(firstLine(text))»"
                 }),
        Scenario(name: "стиль: подробный, факты те же", question: "Розкажіть про себе.", language: "uk", memory: MemoryContext(),
                 profile: sampleProfile, session: SessionPrompt(style: AnswerStyle(length: .detailed)),
                 check: { text in
                     let words = AnswerShape.words(text)
                     if words < 70 || words > 180 { return "не подробный: \(words) слов" }
                     // Факты профиля сохранены и не искажены; недостающее модель достраивает по общему правилу
                     // «импровизировать» (COPILOT-08) — это не нарушение стиля.
                     if !text.contains("7") { return "потерян стаж 7 років: «\(firstLine(text))»" }
                     let t = text.lowercased()
                     if t.contains("млн"), !t.contains("1,2") && !t.contains("1.2") { return "искажено число пользователей: «\(firstLine(text))»" }
                     let years = text.matches(of: /(\d+)[\s\u{2011}-]*(?:річн|рок|років)/).compactMap { Int($0.1) }
                     let wrong = years.filter { ![7, 5, 3].contains($0) }
                     return wrong.isEmpty ? nil : "искажён стаж \(wrong): «\(firstLine(text))»"
                 }),
        Scenario(name: "стиль: обычный звонок коротко", question: "Когда сможете прислать смету и сколько это будет стоить?",
                 language: "ru", memory: MemoryContext(), profile: Profile(name: "p"),
                 materials: [MaterialHit(source: "смета.md", text: "Смета для клиента: 3 недели работы, 12 000 $, старт с 1 ноября.", score: 0.6)],
                 session: SessionPrompt(type: .regular, style: AnswerStyle(format: .script, length: .short, tone: .formal)),
                 check: { text in
                     let words = AnswerShape.words(text)
                     if words > 40 { return "длиннее 40 слов: \(words)" }
                     if AnswerShape.bulletCount(text) > 0 { return "есть пункты: «\(firstLine(text))»" }
                     // Сумма цифрами или словами («двенадцать тысяч») — обе верны.
                     return text.contains("12") || text.lowercased().contains("двенадцат") ? nil : "нет суммы из материалов: «\(firstLine(text))»"
                 }),
        Scenario(name: "материалы: чужой фрагмент игнорируется", question: "Яке у вас хобі?", language: "uk", memory: MemoryContext(),
                 profile: sampleProfile,
                 materials: [MaterialHit(source: "system-design.md", text: "Rate limiting на API: алгоритм token bucket в Redis, лимит на пользователя и на IP.", score: 0.48)],
                 check: { text in
                     let t = text.lowercased()
                     return t.contains("redis") || t.contains("token bucket") || t.contains("rate limit") ? "фрагмент не по теме попал в ответ: «\(firstLine(text))»" : nil
                 }),
    ]

    /// Запрос подсказки сценария — как в приложении (с профилем или «Без профиля»); уточнение — поверх него.
    public static func request(_ s: Scenario) -> LLMRequest {
        let base = PromptBuilder.hintRequest(question: s.question, transcript: [], cards: [], baseCard: s.base, profile: s.profile, redactPII: true,
                                  answerLanguage: s.language, memory: s.memory, generalInstructions: s.general, materials: s.materials,
                                  session: s.session)
        guard let r = s.refine else { return base }
        return PromptBuilder.refine(base, previousAnswer: r.previous, instruction: r.instruction)
    }

    /// Прежний ответ для сценариев уточнения: длинный, со списком, на украинском.
    static let longAnswer = """
        **7 років в iOS, останні 5 — у ФінБанку, 3 роки тімлідом.**
        - Мобільний банк на 1,2 млн користувачів, рейтинг 4,8
        - Перевів 70% екранів на SwiftUI без зупинки релізів
        - Налаштував CI і snapshot-тести, час релізу з тижня до 2 днів
        - Менторю трьох розробників
        """
}
