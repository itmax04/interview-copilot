import AppKit
import Foundation
import Testing
@testable import CopilotCore

@Suite("Профили и загрузка файлов — COPILOT-08 R-01, R-02")
struct ProfileLibraryTests {
    static let exampleURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../profile.example").standardized

    func temp(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    func permissions(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber)?.intValue ?? -1
    }

    @Test func createListRenameDelete() throws {
        let root = temp("profiles")
        defer { try? FileManager.default.removeItem(at: root) }
        let lib = ProfileLibrary(root: root)
        let ios = try lib.create(name: "iOS в банк")
        let backend = try lib.create(name: "Backend стартап")
        let again = try lib.create(name: "iOS в банк")
        #expect(ios.id == "ios-v-bank" && again.id == "ios-v-bank-2")
        #expect(lib.list().map(\.name) == ["Backend стартап", "iOS в банк", "iOS в банк"])
        #expect(permissions(lib.directory(ios.id)) == 0o700)
        #expect(permissions(lib.directory(ios.id).appendingPathComponent("resume.md")) == 0o600)
        // Новый профиль — пустой и правильный: пустая база вопросов читается.
        #expect(try QuestionBankParser.load(lib.questionsURL(backend.id)).isEmpty)
        #expect(lib.load(backend.id).resume.isEmpty && lib.load(backend.id).name == "Backend стартап")
        try lib.write("Swift 7 лет", .resume, of: ios.id)
        try lib.write("Отвечай коротко", .instructions, of: ios.id)
        try lib.rename(ios.id, to: "iOS — финтех")
        let loaded = lib.load(ios.id)
        #expect(loaded.name == "iOS — финтех" && loaded.resume == "Swift 7 лет" && loaded.instructions == "Отвечай коротко")
        try lib.delete(again.id)
        #expect(lib.list().count == 2)
        #expect(ProfileLibrary.slug("Мой профиль") == "moj-profil" || ProfileLibrary.slug("Мой профиль").hasPrefix("moj"))
        #expect(ProfileLibrary.slug("日本") != "")
        #expect(ProfileLibrary.cleanName("   ") == ProfileLibrary.defaultName)
    }

    @Test func unchangedExampleIsRemovedAndOwnDataIsMoved() throws {
        let base = temp("legacy")
        defer { try? FileManager.default.removeItem(at: base) }
        let lib = ProfileLibrary(root: base.appendingPathComponent("profiles"))
        // Старая папка — копия примера (как у владельца): удаляется (Q12).
        let legacy = base.appendingPathComponent("profile")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.exampleURL, to: legacy)
        #expect(try lib.migrateLegacy(legacy, example: Self.exampleURL) == .removedExample)
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(lib.list().isEmpty)
        // Изменённая — переносится в профиль целиком.
        try FileManager.default.copyItem(at: Self.exampleURL, to: legacy)
        try "Моё настоящее резюме".write(to: legacy.appendingPathComponent("resume.md"), atomically: true, encoding: .utf8)
        guard case .moved(let info) = try lib.migrateLegacy(legacy, example: Self.exampleURL) else {
            Issue.record("ожидался перенос"); return
        }
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(lib.load(info.id).resume == "Моё настоящее резюме")
        #expect(try QuestionBankParser.load(lib.questionsURL(info.id)).count == 20)
        #expect(try lib.migrateLegacy(legacy, example: Self.exampleURL) == .none)
    }

    @Test func generalInstructionsRoundTrip() throws {
        let url = temp("instr").appendingPathComponent("instructions.md")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(ProfileLibrary.readGeneralInstructions(at: url).isEmpty)
        try ProfileLibrary.writeGeneralInstructions("Отвечай на английском", at: url)
        #expect(ProfileLibrary.readGeneralInstructions(at: url) == "Отвечай на английском")
        #expect(permissions(url) == 0o600)
    }

    // MARK: Извлечение текста (R-02)

    static let sample = "Іван Петренко — Senior iOS Developer\nДосвід: 7 років, Swift, SwiftUI\nПроєкт: мобільний банк, 1,2 млн користувачів"

    /// PDF с текстовым слоем, нарисованный CoreText (как экспорт из Word/Pages).
    static func makePDF(_ text: String?, at url: URL) {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        if let text {
            let attr = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12)])
            let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(attr), CFRange(location: 0, length: 0),
                                                 CGPath(rect: box.insetBy(dx: 40, dy: 40), transform: nil), nil)
            CTFrameDraw(frame, ctx)
        } else {
            ctx.setFillColor(NSColor.gray.cgColor)   // «скан»: только картинка, текста нет
            ctx.fill(CGRect(x: 40, y: 40, width: 300, height: 200))
        }
        ctx.endPDFPage()
        ctx.closePDF()
    }

    @Test func extractsTextFromPdfWordRtfAndPlainText() throws {
        let dir = temp("docs")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let attributed = NSAttributedString(string: Self.sample)
        let pdf = dir.appendingPathComponent("cv.pdf")
        Self.makePDF(Self.sample, at: pdf)
        let docx = dir.appendingPathComponent("cv.docx")
        try attributed.data(from: NSRange(location: 0, length: attributed.length),
                            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]).write(to: docx)
        let rtf = dir.appendingPathComponent("cv.rtf")
        try attributed.data(from: NSRange(location: 0, length: attributed.length),
                            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]).write(to: rtf)
        let txt = dir.appendingPathComponent("cv.txt")
        try ("  " + Self.sample + "  \r\n\r\n\r\n\u{00A0}Кінець").write(to: txt, atomically: true, encoding: .utf8)
        let md = dir.appendingPathComponent("notes.MD")
        try "# Нотатки\n\n- пункт".write(to: md, atomically: true, encoding: .utf8)

        for url in [pdf, docx, rtf] {
            let text = try DocumentText.extract(from: url)
            #expect(text.contains("Senior iOS Developer"), "\(url.lastPathComponent)")
            #expect(text.contains("мобільний банк"), "\(url.lastPathComponent)")
        }
        #expect(try DocumentText.extract(from: txt) == Self.sample + "\n\nКінець")
        #expect(try DocumentText.extract(from: md) == "# Нотатки\n\n- пункт")
    }

    @Test func scanAndUnsupportedFormatGiveClearErrors() throws {
        let dir = temp("bad")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let scan = dir.appendingPathComponent("scan.pdf")
        Self.makePDF(nil, at: scan)
        #expect(throws: DocumentTextError.noText("scan.pdf")) { try DocumentText.extract(from: scan) }
        let pages = dir.appendingPathComponent("cv.pages")
        try Data([1, 2]).write(to: pages)
        #expect(throws: DocumentTextError.unsupported("pages")) { try DocumentText.extract(from: pages) }
        let broken = dir.appendingPathComponent("broken.pdf")
        try Data("not a pdf".utf8).write(to: broken)
        #expect(throws: DocumentTextError.unreadable("broken.pdf")) { try DocumentText.extract(from: broken) }
        #expect(DocumentTextError.noText("scan.pdf").description.contains("скан"))
    }

    @Test func importKeepsSourceAndSavesText() throws {
        let root = temp("import")
        defer { try? FileManager.default.removeItem(at: root) }
        let lib = ProfileLibrary(root: root)
        let p = try lib.create(name: "Тест")
        let pdf = root.appendingPathComponent("my cv.pdf")
        Self.makePDF(Self.sample, at: pdf)
        let text = try lib.importFile(pdf, as: .resume, into: p.id)
        #expect(lib.read(.resume, of: p.id) == text)
        let source = lib.sourcesDirectory(p.id).appendingPathComponent("resume.pdf")
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(permissions(source) == 0o600)
    }
}

@Suite("Инструкции владельца в промпте — COPILOT-08 R-04, R-05")
struct OwnerInstructionsPromptTests {
    @Test func instructionsBlockFollowsProfileAndWinsOverStyle() {
        let profile = Profile(name: "p", resume: "Swift 7 лет", instructions: "Отвечай 2 предложениями. Почта me@example.com")
        let s = PromptBuilder.system(profile: profile, redactPII: true, generalInstructions: "Акцент на лидерстве")
        #expect(s.contains("<owner_instructions>\n<general>\nАкцент на лидерстве\n</general>\n<profile_specific>\nОтвечай 2 предложениями."))
        #expect(s.contains("They take priority over the rules above"))
        #expect(s.contains("never confirm what the candidate did not say"))
        #expect(!s.contains("me@example.com"))                  // фильтр ПД и для инструкций (R-10)
        // Последним в системной части — после профиля.
        #expect(s.range(of: "</profile>")!.lowerBound < s.range(of: "<owner_instructions>")!.lowerBound)
        // Без профиля — общие инструкции всё равно действуют.
        let none = PromptBuilder.system(profile: nil, redactPII: true, generalInstructions: "Отвечай на английском")
        #expect(none.contains("<general>\nОтвечай на английском\n</general>") && !none.contains("<profile_specific>"))
        // Инструкций нет — блока нет.
        #expect(!PromptBuilder.system(profile: Profile(name: "p"), redactPII: true).contains("owner_instructions"))
    }

    @Test func requestAllowsLongerAnswersAndLanguageOverride() {
        let plain = PromptBuilder.hintRequest(question: "q", transcript: [], cards: [], baseCard: nil, profile: Profile(name: "p"),
                                              redactPII: false, answerLanguage: "uk")
        #expect(plain.maxTokens == 400 && !plain.messages[0].text.contains("owner's instructions set the answer language"))
        let instructed = PromptBuilder.hintRequest(question: "q", transcript: [], cards: [], baseCard: nil, profile: Profile(name: "p"),
                                                   redactPII: false, answerLanguage: "uk", generalInstructions: "Відповідай англійською")
        #expect(instructed.maxTokens == 800)
        #expect(instructed.messages[0].text.contains("If the owner's instructions set the answer language, follow them instead."))
        #expect(instructed.system.contains("<general>\nВідповідай англійською"))
    }

    @Test func missingFactsAreImprovisedFreely() {
        let s = PromptBuilder.system(profile: Profile(name: "p", resume: "r"), redactPII: false)
        #expect(s.contains("When a needed fact or story is missing, improvise freely"))
        #expect(!s.contains("preferring general wording over invented company names"))
        #expect(s.contains("it is the candidate's own prepared answer to a similar question"))
    }

    @Test func activeProfileSettingPersists() throws {
        var s = AppSettings()
        s.activeProfileID = "ios-v-bank"
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back.activeProfileID == "ios-v-bank")
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).activeProfileID == nil)
    }
}
