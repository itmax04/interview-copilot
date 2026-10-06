import Foundation
import Testing
@testable import CopilotCore

@Suite("ModelDownloader — R-22")
struct ModelDownloaderTests {
    static let listURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../models.sha256").standardized

    @Test func parsesRepositoryList() throws {
        let list = ModelFile.parseList(try String(contentsOf: Self.listURL, encoding: .utf8))
        #expect(list.contains { $0.file == "ggml-small-q5_1.bin" && $0.size == 190_085_487 && $0.sha256.count == 64 })
        #expect(list.contains { $0.file == "bge-m3-q8_0.gguf" })
        #expect(list.allSatisfy { $0.url.scheme == "https" }) // только HTTPS (модель угроз)
    }

    /// Живая загрузка маленького файла по HTTPS (сеть нужна; без сети тест помечается пропущенным).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["INTERVIEWCOPILOT_OFFLINE"] == nil))
    func downloadsAndVerifies() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let entry = ModelFile(sha256: "94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d", file: "LICENSE", size: 1078, url: URL(string: "https://raw.githubusercontent.com/ggml-org/llama.cpp/b11446/LICENSE")!)
        let d = ModelDownloader(directory: dir, list: [entry])
        try await d.download("LICENSE") { _ in }
        #expect(d.isPresent("LICENSE"))
        let wrong = ModelDownloader(directory: dir, list: [ModelFile(sha256: String(repeating: "a", count: 64), file: "X", size: 1078, url: entry.url)])
        await #expect(throws: ModelDownloadError.checksumMismatch("X")) { try await wrong.download("X") { _ in } }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("X").path))
    }

    @Test func checksumMismatchDeletesFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("models-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = Data("подменённый файл".utf8)
        try data.write(to: dir.appendingPathComponent("m.bin"))
        let good = try ModelDownloader.sha256(of: dir.appendingPathComponent("m.bin"))
        let ok = ModelDownloader(directory: dir, list: [ModelFile(sha256: good, file: "m.bin", size: Int64(data.count), url: URL(string: "https://example.com/m.bin")!)])
        try ok.verify("m.bin")
        #expect(ok.isPresent("m.bin"))
        let bad = ModelDownloader(directory: dir, list: [ModelFile(sha256: String(repeating: "0", count: 64), file: "m.bin", size: Int64(data.count), url: URL(string: "https://example.com/m.bin")!)])
        #expect(throws: ModelDownloadError.checksumMismatch("m.bin")) { try bad.verify("m.bin") }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("m.bin").path))
    }
}
