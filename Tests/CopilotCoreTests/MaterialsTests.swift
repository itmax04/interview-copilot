import Foundation
import Testing
@testable import CopilotCore

/// Детерминированный эмбеддинг по ключевым словам — без модели.
final class KeywordEmbedder: TextEmbedder, @unchecked Sendable {
    let identifier = "keywords-test"
    let words = ["actor", "кеш", "платеж", "kafka"]
    private(set) var calls = 0
    func embed(_ texts: [String]) throws -> [[Float]] {
        calls += texts.count
        return texts.map { t in
            let l = t.lowercased()
            return (words.map { l.contains($0) ? Float(1) : 0 } + [0.1]).normalized()
        }
    }
}

@Suite("Материалы профиля — COPILOT-08 R-06")
struct MaterialsTests {
    @Test func chunksFollowParagraphsAndLimits() {
        let p1 = String(repeating: "Actor захищає стан. ", count: 15)          // ~300 символов — свой фрагмент
        let p2 = String(repeating: "Кеш з TTL. ", count: 30)                   // ~330
        let title = "# Конспект"
        let chunks = MaterialChunker.chunks("\(title)\n\n\(p1)\n\n\(p2)")
        #expect(chunks.count == 2)
        #expect(chunks[0].hasPrefix("# Конспект\n"))                           // заголовок прилип к первому абзацу
        // Длинный абзац режется по предложениям, ни один фрагмент не длиннее лимита.
        let long = String(repeating: "Це довге речення про платежі та ідемпотентність запитів. ", count: 40)
        let parts = MaterialChunker.chunks(long)
        #expect(parts.count > 2 && parts.allSatisfy { $0.count <= MaterialChunker.maxCharacters })
        // Слово-гигант без пробелов не ломает нарезку.
        #expect(MaterialChunker.chunks(String(repeating: "x", count: 3000)).allSatisfy { $0.count <= MaterialChunker.maxCharacters })
        #expect(MaterialChunker.chunks("  \n\n ").isEmpty)
    }

    @Test func indexFindsFragmentCachesVectorsAndLimitsOutput() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mat-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = dir.appendingPathComponent("index.plist")
        let e = KeywordEmbedder()
        let files = [(source: "swift.md", text: "Actor захищає стан від гонок.\n\nКеш інвалідуємо видаленням ключа."),
                     (source: "pay.md", text: "Ключ ідемпотентності для кожного платежу.")]
        let index = try MaterialIndexBuilder(embedder: e, cacheURL: cache).build(files)
        #expect(index.entries.count == 2 && e.calls == 2)   // два коротких абзаца swift.md — один фрагмент
        let hits = index.search(try e.embed(["Що таке actor?"])[0])
        #expect(hits.first?.source == "swift.md" && hits.first?.text.contains("Actor") == true)
        #expect(index.search(try e.embed(["Хобі?"])[0]).isEmpty)              // не по теме — ничего
        // Повторная сборка — из кэша, без новых эмбеддингов; права файла кэша 600.
        let again = KeywordEmbedder()
        _ = try MaterialIndexBuilder(embedder: again, cacheURL: cache).build(files)
        #expect(again.calls == 0)
        #expect(((try FileManager.default.attributesOfItem(atPath: cache.path)[.posixPermissions]) as? NSNumber)?.intValue == 0o600)
        // Отмена между пачками.
        #expect(throws: CancellationError.self) {
            try MaterialIndexBuilder(embedder: KeywordEmbedder(), cacheURL: nil).build(files, isCancelled: { true })
        }
    }

    @Test func searchRespectsCountAndCharacterBudget() {
        let v: [Float] = [1, 0]
        let big = String(repeating: "a", count: 1500)
        let index = MaterialIndex(entries: (0..<6).map { MaterialIndex.Entry(source: "s\($0)", text: big, vector: v) })
        let hits = index.search(v)
        #expect(hits.count == 2)                                                // 2 × 1500 ≤ 3200, третий не влезает
        let small = MaterialIndex(entries: (0..<6).map { MaterialIndex.Entry(source: "s\($0)", text: "t", vector: v) })
        #expect(small.search(v).count == MaterialIndex.limit)
    }

    @Test func libraryAddsListsAndRemovesMaterials() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mlib-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let lib = ProfileLibrary(root: root)
        let p = try lib.create(name: "Тест")
        let src = root.appendingPathComponent("notes.txt")
        try "Actor захищає стан.".write(to: src, atomically: true, encoding: .utf8)
        let added = try lib.addMaterial(src, into: p.id)
        #expect(added == MaterialFile(name: "notes.txt", characters: 19))
        #expect(lib.listMaterials(p.id) == [added])
        #expect(lib.materialTexts(p.id).first?.text == "Actor захищає стан.")
        #expect(FileManager.default.fileExists(atPath: lib.materialsDirectory(p.id).appendingPathComponent("sources/notes.txt").path))
        try lib.removeMaterial("notes.txt", from: p.id)
        #expect(lib.listMaterials(p.id).isEmpty)
        let scan = root.appendingPathComponent("scan.pdf")
        ProfileLibraryTests.makePDF(nil, at: scan)
        #expect(throws: DocumentTextError.noText("scan.pdf")) { try lib.addMaterial(scan, into: p.id) }
    }

    @Test func promptGetsExcerptsAsDataWithPIIFiltered() {
        let hits = [MaterialHit(source: "notes \"v2\".md", text: "RabbitMQ: 2 млн повідомлень. Пишіть ivan@example.com", score: 0.6)]
        let r = PromptBuilder.hintRequest(question: "Скільки повідомлень?", transcript: [], cards: [], baseCard: nil,
                                          profile: Profile(name: "p"), redactPII: true, materials: hits)
        let u = r.messages[0].text
        #expect(u.contains("<materials>\n<excerpt source=\"notes 'v2'.md\">\nRabbitMQ: 2 млн повідомлень."))
        #expect(!u.contains("ivan@example.com"))
        #expect(r.system.contains("<materials> are excerpts from the candidate's own notes"))
        #expect(r.system.contains("<profile>, <cards>, <materials>, <transcript>"))
        #expect(!PromptBuilder.user(question: "q", transcript: [], cards: [], baseCard: nil).contains("<materials>"))
    }
}
