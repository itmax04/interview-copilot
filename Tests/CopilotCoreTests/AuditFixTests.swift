import Foundation
import Testing
@testable import CopilotCore

@Suite("COPILOT-13 — срок хранения истории")
struct SessionPurgeTests {
    func makeStore() -> (SessionStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("copilot-purge-\(UUID().uuidString)")
        return (SessionStore(directory: dir), dir)
    }

    func session(_ store: SessionStore, at date: Date) -> SessionRecord {
        var s = store.newSession(source: "Zoom", at: date)
        s.utterances = [.init(id: 1, text: "вопрос", language: "ru", at: date)]
        s.endedAt = date.addingTimeInterval(600)
        return s
    }

    /// Нечитаемый файл раньше переживал срок хранения навсегда.
    @Test func unreadableOldFileIsPurged() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()
        try store.save(session(store, at: now.addingTimeInterval(-3600)))
        let broken = dir.appendingPathComponent("2020-01-01T10-00-00.json")
        try Data("{ not json".utf8).write(to: broken)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-40 * 86_400)], ofItemAtPath: broken.path)
        #expect(store.purge(olderThan: 30, now: now) == 1)
        #expect(!FileManager.default.fileExists(atPath: broken.path))
        #expect(store.list().count == 1)
    }

    /// Свежий нечитаемый файл не трогаем: срок ещё не вышел.
    @Test func unreadableFreshFileIsKept() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let broken = dir.appendingPathComponent("broken.json")
        try Data("{ not json".utf8).write(to: broken)
        #expect(store.purge(olderThan: 30) == 0)
        #expect(FileManager.default.fileExists(atPath: broken.path))
    }

    /// Сессия, начатая по имени файла давно, но законченная недавно (долгая запись, правка разбора), остаётся:
    /// решает время окончания из файла, а имя только избавляет от чтения заведомо свежих.
    @Test func endedAtDecidesForOldNames() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date(timeIntervalSince1970: 1_791_300_000)
        var long = store.newSession(source: nil, at: now.addingTimeInterval(-31 * 86_400))
        long.utterances = [.init(id: 1, text: "вопрос", language: "ru", at: now)]
        long.endedAt = now.addingTimeInterval(-29 * 86_400)
        try store.save(long)
        #expect(store.purge(olderThan: 30, now: now) == 0)
        #expect(store.list().map(\.id) == [long.id])
    }

    @Test func startDateFromFileName() {
        #expect(SessionStore.startDate(fromFileName: "2026-10-06T14-30-05") != nil)
        #expect(SessionStore.startDate(fromFileName: "2026-10-06T14-30-05-2") == SessionStore.startDate(fromFileName: "2026-10-06T14-30-05"))
        #expect(SessionStore.startDate(fromFileName: "broken") == nil)
    }
}

@Suite("COPILOT-13 — страница вакансии")
struct JobPageDecodingTests {
    @Test func ampersandIsDecodedOnceAndLast() {
        #expect(JobImport.decodeEntities("a &amp;lt; b") == "a &lt; b")
        #expect(JobImport.decodeEntities("R&amp;D &lt;team&gt;") == "R&D <team>")
        #expect(JobImport.decodeEntities("&amp;#39;") == "&#39;")
    }

    @Test func numericEntitiesBecomeCharacters() {
        #expect(JobImport.decodeEntities("&#1055;&#1088;&#1080;&#1074;&#1077;&#1090;") == "Привет")
        #expect(JobImport.decodeEntities("Go &#x2014; Kafka") == "Go — Kafka")
        #expect(JobImport.decodeEntities("a&#0;b&#7;c") == "a b c")
        #expect(JobImport.decodeEntities("&#99999999;") == "&#99999999;")
    }

    @Test func pageTextKeepsNumericCyrillic() {
        let html = "<html><body><p>&#1058;&#1088;&#1077;&#1073;&#1086;&#1074;&#1072;&#1085;&#1080;&#1103;: Swift &amp; Kotlin</p></body></html>"
        #expect(JobImport.text(fromHTML: html) == "Требования: Swift & Kotlin")
    }

    @Test func windows1251FromHeaderAndMeta() throws {
        let text = "<html><head><meta charset=\"windows-1251\"></head><body>Требования к кандидату</body></html>"
        let data = try #require(text.data(using: .windowsCP1251))
        #expect(JobImport.decode(data, encodingName: "windows-1251").contains("Требования к кандидату"))
        #expect(JobImport.decode(data, encodingName: nil).contains("Требования к кандидату"))
        #expect(JobImport.metaCharset(data) == "windows-1251")
    }

    @Test func utf8IsDefault() {
        let data = Data("<html><body>Вимоги до кандидата</body></html>".utf8)
        #expect(JobImport.decode(data, encodingName: nil).contains("Вимоги до кандидата"))
        #expect(JobImport.decode(data, encodingName: "utf-8").contains("Вимоги до кандидата"))
        #expect(JobImport.decode(data, encodingName: "no-such-charset").contains("Вимоги до кандидата"))
    }
}

@Suite("COPILOT-13 — кольцевой буфер блоками")
struct RingBufferBlockCopyTests {
    /// Запись и чтение через границу кольца совпадают с посэмпловой моделью.
    @Test func wrapAroundMatchesReference() {
        let buffer = AudioRingBuffer(seconds: 0.01, sampleRate: 1_000) // 10 сэмплов
        var reference: [Float] = []
        var next: Float = 0
        for size in [3, 4, 5, 1, 9, 10, 7, 2, 25, 6] {
            let chunk = (0..<size).map { _ -> Float in next += 1; return next }
            buffer.append(chunk)
            reference += chunk
            let end = Int64(reference.count)
            #expect(buffer.endPosition == end)
            #expect(buffer.read(from: 0) == Array(reference.suffix(10)))
            #expect(buffer.read(from: end - 4) == Array(reference.suffix(min(4, reference.count))))
            #expect(buffer.read(from: end - 7, to: end - 2) == Array(reference.suffix(min(7, reference.count)).dropLast(2)))
        }
        #expect(buffer.read(from: 100).isEmpty)
    }
}
