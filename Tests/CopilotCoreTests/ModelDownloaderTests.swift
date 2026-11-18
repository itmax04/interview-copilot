import CryptoKit
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

    @Test @MainActor func simultaneousDownloadsKeepTheirOwnFilesAndProgress() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let payloads = ["a": Data(repeating: 1, count: 300_000), "b": Data(repeating: 2, count: 600_000)]
        let server = try LocalTestCallServer { request in
            try? await Task.sleep(for: .milliseconds(100))
            let name = String(request.path.dropFirst())
            guard let body = payloads[name] else { return .error(404, "Unknown fixture") }
            return LocalHTTPResponse(body: body, contentType: "application/octet-stream")
        }
        defer { server.stop() }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            server.start(onReady: { continuation.resume(returning: $0) },
                         onError: { _ in continuation.resume(throwing: URLError(.cannotConnectToHost)) })
        }
        let entries = payloads.map { name, data in
            ModelFile(sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                      file: name, size: Int64(data.count), url: URL(string: "http://127.0.0.1:\(port)/\(name)")!)
        }
        let downloader = ModelDownloader(directory: directory, list: entries)
        var finished = Set<String>(), progressed = Set<String>()
        for entry in entries {
            Task {
                do {
                    try await downloader.download(entry.file) { fraction in
                        if fraction > 0 { Task { @MainActor in progressed.insert(entry.file) } }
                    }
                    finished.insert(entry.file)
                } catch { Issue.record("Download failed: \(error)") }
            }
        }
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while clock.now < deadline && (finished.count < entries.count || progressed.count < entries.count) {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(finished == Set(payloads.keys))
        #expect(progressed == Set(payloads.keys))
        for (name, data) in payloads {
            #expect(try Data(contentsOf: directory.appendingPathComponent(name)) == data)
        }
        let prior = try #require(entries.first)
        var invalid = prior
        invalid.sha256 = String(repeating: "0", count: 64)
        let badHash = ModelDownloader(directory: directory, list: [invalid])
        await #expect(throws: ModelDownloadError.checksumMismatch(prior.file)) { try await badHash.download(prior.file) { _ in } }
        invalid.url = prior.url.deletingLastPathComponent().appendingPathComponent("missing")
        let missing = ModelDownloader(directory: directory, list: [invalid])
        await #expect(throws: ModelDownloadError.http(404)) { try await missing.download(prior.file) { _ in } }
        #expect(try Data(contentsOf: directory.appendingPathComponent(prior.file)) == payloads[prior.file])
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)) == Set(payloads.keys))
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
