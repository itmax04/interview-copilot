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
        case .unsupported(let ext): "Формат .\(ext) не поддерживается: PDF, Word (.docx), RTF, TXT или Markdown"
        case .unreadable(let file): "Не удалось прочитать «\(file)»"
        case .noText(let file): "В «\(file)» нет текста. Если это скан, сохраните документ с текстовым слоем или вставьте текст вручную"
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
        let lines = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
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
