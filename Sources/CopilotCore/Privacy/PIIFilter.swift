import Foundation

/// Фильтр личных данных — R-12: перед отправкой из профиля удаляются email, телефоны и URL.
public enum PIIFilter {
    static let email = try! NSRegularExpression(pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#)
    /// Ссылки: со схемой или www, а также домен с путём (linkedin.com/in/…, github.com/…, t.me/…).
    /// Голые «Socket.io», «ASP.NET» не трогаем — это названия технологий.
    static let url = try! NSRegularExpression(pattern: #"(?i)\b(?:https?://|www\.)[^\s<>()\[\]]+|\b[a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,}/[^\s<>()\[\]]+"#)
    /// Телефоны: 10–13 цифр с типичной группировкой, а не диапазоны лет («2019-2022») и числа («1 200 000»).
    static let phone = try! NSRegularExpression(pattern: #"(?<![\w+])(?:\+\d{1,3}[\s.-]?)?\(?\d{2,3}\)?[\s.-]?\d{3}[\s.-]?\d{2}[\s.-]?\d{2}(?![\w])"#)

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
