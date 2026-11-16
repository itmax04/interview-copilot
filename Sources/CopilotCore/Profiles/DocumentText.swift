import AppKit
import Foundation
import PDFKit

public enum DocumentTextError: Error, Equatable, CustomStringConvertible {
    case unsupported(String)
    case unreadable(String)
    /// PDF без текстового слоя (скан) или пустой файл.
    case noText(String)

    public var description: String {
        switch self {
        case .unsupported(let ext): L10n.f("Формат .%@ не поддерживается: PDF, Word (.docx), RTF, TXT или Markdown", ext)
        case .unreadable(let file): L10n.f("Не удалось прочитать «%@»", file)
        case .noText(let file): L10n.f("В «%@» нет текста. Если это скан, сохраните документ с текстовым слоем или вставьте текст вручную", file)
        }
    }
}

/// Текст из загруженного файла — COPILOT-08 R-02. Всё локально и системными средствами (без новых зависимостей):
/// PDF — PDFKit, .docx и .rtf — `NSAttributedString` (AppKit), .txt и .md — как есть.
public enum DocumentText {
    public static let supportedExtensions = ["pdf", "docx", "rtf", "txt", "md", "markdown"]

    public static func extract(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent
        let raw: String
        switch ext {
        case "pdf":
            guard let document = PDFDocument(url: url) else { throw DocumentTextError.unreadable(name) }
            raw = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n\n")
        case "docx", "rtf":
            let type: NSAttributedString.DocumentType = ext == "docx" ? .officeOpenXML : .rtf
            guard let text = try? NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil) else {
                throw DocumentTextError.unreadable(name)
            }
            raw = text.string
        case "txt", "md", "markdown":
            var encoding = String.Encoding.utf8
            guard let text = try? String(contentsOf: url, usedEncoding: &encoding) else { throw DocumentTextError.unreadable(name) }
            raw = text
        default:
            throw DocumentTextError.unsupported(ext.isEmpty ? "?" : ext)
        }
        let text = normalize(raw)
        guard !text.isEmpty else { throw DocumentTextError.noText(name) }
        return text
    }

    /// Пробелы в конце строк, неразрывные пробелы и больше одной пустой строки подряд убираются.
    static func normalize(_ s: String) -> String {
        let lines = PlainText.unifiedLineBreaks(s)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        var out: [String] = []
        for line in lines {
            if line.isEmpty, out.last?.isEmpty ?? true { continue }
            out.append(line)
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Текст без символов, которые ломают разбор по строкам и запись в YAML (COPILOT-13).
public enum PlainText {
    /// Все разрывы строк — «\n». Word и Pages отдают мягкий перенос как U+2028, абзац — U+2029, разрыв страницы — U+000C,
    /// перенос внутри ячейки — U+000B: без замены строки файла вопросов склеивались в одну.
    public static func unifiedLineBreaks(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        var afterCR = false
        for u in s.unicodeScalars {
            switch u.value {
            case 0x0A: if !afterCR { out.append("\n") }   // «\r\n» — один перевод строки
            case 0x0D, 0x0B, 0x0C, 0x85, 0x2028, 0x2029: out.append("\n")
            default: out.append(u)
            }
            afterCR = u.value == 0x0D
        }
        return String(out)
    }

    /// Только символы, допустимые в YAML: разрывы строк приведены к «\n», прочие управляющие символы убраны.
    public static func printable(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in unifiedLineBreaks(s).unicodeScalars {
            switch u.value {
            case 0x09, 0x0A, 0x20...0x7E, 0xA0...0xD7FF, 0xE000...0xFEFE, 0xFF00...0xFFFD, 0x1_0000...0x10_FFFF: out.append(u)
            default: break
            }
        }
        return String(out)
    }
}
