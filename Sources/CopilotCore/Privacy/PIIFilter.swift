import Foundation

/// Фильтр личных данных — R-12: перед отправкой из профиля удаляются email, телефоны и URL.
public enum PIIFilter {
    static let email = try! NSRegularExpression(pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#)
    static let url = try! NSRegularExpression(pattern: #"(?i)\b(?:https?://|www\.)[^\s<>()\[\]]+|\b[a-z0-9-]+\.(?:com|net|org|io|dev|me|ua|ru|app|co)(?:/[^\s<>()]*)?"#)
    static let phone = try! NSRegularExpression(pattern: #"(?<![\w])(?:\+?\d[\d\s().-]{7,}\d)(?![\w])"#)

    public static func redact(_ text: String) -> String {
        var t = replace(email, in: text, with: "[email]")
        t = replace(url, in: t, with: "[ссылка]")
        t = replace(phone, in: t, with: "[телефон]")
        return t
    }

    private static func replace(_ re: NSRegularExpression, in text: String, with template: String) -> String {
        re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
