import Foundation

/// Когда ключ снова можно пробовать после 429: заголовок `retry-after` (Groq — секунды), «Please try again in 6.18s»
/// в тексте ошибки (Groq), `"retryDelay": "34s"` (Gemini). Нужно, чтобы ключ «остывал» ровно до сброса лимита:
/// минутный лимит — секунды, дневной — часы.
public enum RetryHint {
    /// Метка в начале текста ошибки 429: текст режется до 200 символов, а «try again in» у Groq — в самом конце.
    static let prefix = "[retry-after "

    public static func tag(_ seconds: Double) -> String { prefix + String(format: "%.2f", seconds) + "s] " }

    /// Из заголовка и тела ответа 429.
    public static func seconds(header: String?, body: String) -> Double? {
        if let header, let s = Double(header.trimmingCharacters(in: .whitespaces)), s > 0 { return s }
        return seconds(inText: body)
    }

    /// Из текста ошибки: сначала метка, затем фразы провайдеров.
    public static func seconds(inText text: String) -> Double? {
        if let r = text.range(of: prefix), let end = text[r.upperBound...].firstIndex(of: "s"),
           let s = Double(text[r.upperBound..<end]) { return s }
        let lower = text.lowercased()
        if let r = lower.range(of: "try again in ") {
            return duration(String(lower[r.upperBound...].prefix(20)))
        }
        if let r = lower.range(of: #""retrydelay"\s*:\s*"([\d.]+)s""#, options: .regularExpression) {
            let digits = lower[r].filter { $0.isNumber || $0 == "." }
            return Double(digits)
        }
        return nil
    }

    /// «1h2m3.5s», «6.18s», «2m», «750ms».
    static func duration(_ s: String) -> Double? {
        guard let match = s.range(of: #"^(\d+h)?(\d+m(?!s))?([\d.]+s)?([\d.]+ms)?"#, options: .regularExpression), !s[match].isEmpty else { return nil }
        var total = 0.0
        var number = ""
        var unit = ""
        func flush() {
            guard let v = Double(number) else { return }
            switch unit {
            case "h": total += v * 3600
            case "m": total += v * 60
            case "s": total += v
            case "ms": total += v / 1000
            default: break
            }
        }
        for ch in s[match] {
            if ch.isNumber || ch == "." {
                if !unit.isEmpty { flush(); number = ""; unit = "" }
                number.append(ch)
            } else {
                unit.append(ch)
            }
        }
        flush()
        return total > 0 ? total : nil
    }
}
