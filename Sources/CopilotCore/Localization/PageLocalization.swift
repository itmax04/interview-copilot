import Foundation

/// Локальные страницы ИИ-собеседования и тестового звонка на языке интерфейса (COPILOT-10). Словарь — `en.json` рядом со
/// страницей: ключ — русский текст. Разметка до `<script>` переводится целыми фрагментами (текст между тегами и значения
/// атрибутов), строки скрипта — функцией `T(…)` страницы по словарю `window.L10N`, который сюда же подставляется.
public enum PageLocalization {
    public static func table(in directory: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("en.json")),
              let table = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return table
    }

    public static func localize(_ html: String, table: [String: String]) -> String {
        guard !table.isEmpty, let script = html.range(of: "<script>") else { return html }
        var head = String(html[..<script.lowerBound]).replacingOccurrences(of: "<html lang=\"ru\">", with: "<html lang=\"en\">")
        // Сначала длинные фрагменты: короткий («Завершить») не должен задеть длинный («Завершить звонок»).
        for (ru, en) in table.sorted(by: { $0.key.count > $1.key.count }) {
            head = head.replacingOccurrences(of: ">\(ru)<", with: ">\(escape(en))<")
                .replacingOccurrences(of: "=\"\(ru)\"", with: "=\"\(escape(en))\"")
        }
        let json = (try? JSONEncoder().encode(table)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        // `</` внутри строки закрыл бы тег <script>.
        let dictionary = "<script>window.L10N=\(json.replacingOccurrences(of: "</", with: "<\\/"));</script>\n"
        return head + dictionary + html[script.lowerBound...]
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
