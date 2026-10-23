import Foundation

/// Известные «выдумки» Whisper на тишине и шуме (живой лог COPILOT-05, 2026-10-23: «Дякую!» без речи).
/// Модель училась на субтитрах видео, поэтому на пустом звуке пишет концовки роликов. Отбрасываются только
/// короткие реплики (≤ 2,5 с), целиком совпадающие с такой фразой: настоящее «Спасибо» в длинной фразе остаётся.
public enum HallucinationFilter {
    public static let maxAudioSeconds = 2.5

    static let phrases: Set<String> = [
        // uk
        "дякую", "дякую за перегляд", "дякую за увагу", "дякую за підписку", "підписуйтесь на канал",
        "субтитри створено спільнотою amara.org", "продовження буде",
        // ru
        "спасибо", "спасибо за просмотр", "спасибо за внимание", "продолжение следует", "подписывайтесь на канал",
        "субтитры сделал dimatorzok", "редактор субтитров а.семкин корректор а.егорова", "субтитры создавал dimatorzok",
        // en
        "thank you", "thanks for watching", "thank you for watching", "please subscribe", "you", "bye",
    ]

    public static func isLikely(_ text: String, audioSeconds: Double) -> Bool {
        guard audioSeconds <= maxAudioSeconds else { return false }
        let normalized = text.lowercased()
            .components(separatedBy: CharacterSet.letters.union(.whitespaces).union(CharacterSet(charactersIn: ".")).inverted).joined()
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return !normalized.isEmpty && phrases.contains(normalized)
    }
}
