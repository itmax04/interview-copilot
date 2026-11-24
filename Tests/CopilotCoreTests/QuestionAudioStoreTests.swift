import Foundation
import Testing
@testable import CopilotCore

/// COPILOT-17 R-09/R-10. Данные синтетические.
@Suite struct QuestionAudioStoreTests {
    private func tmp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("qa-\(UUID().uuidString)", isDirectory: true) }
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func sidecar() -> QuestionAudioStore.Sidecar { .init(durationSeconds: 1, language: "uk", decodeMs: 80) }
    private func perms(_ u: URL) -> Int { ((try? FileManager.default.attributesOfItem(atPath: u.path)[.posixPermissions]) as? Int) ?? -1 }

    @Test func savesWavAndNumbersOnlySidecar() throws {
        let dir = tmp(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = QuestionAudioStore(directory: dir)
        let samples = [Float](repeating: 0.25, count: 16_000)
        let size = store.save(samples: samples, turn: 7, sessionStart: start, sidecar: sidecar())
        #expect(size == 44 + 32_000)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names.count == 2)
        #expect(names.allSatisfy { $0.hasSuffix("-7.wav") || $0.hasSuffix("-7.json") })
        let wav = try Data(contentsOf: dir.appendingPathComponent(names.first { $0.hasSuffix(".wav") }!))
        #expect(String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF")
        #expect(wav.count == 44 + 32_000)
        #expect(wav.subdata(in: 22..<24) == Data([1, 0]))                 // моно
        #expect(wav.subdata(in: 24..<28) == Data([0x80, 0x3E, 0, 0]))     // 16000 Гц
        #expect(wav.subdata(in: 34..<36) == Data([16, 0]))                // 16 бит
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent(names.first { $0.hasSuffix(".json") }!))) as! [String: Any]
        #expect(Set(json.keys) == ["durationSeconds", "sampleRate", "language", "channel", "decodeMs"])
        #expect(perms(dir) == 0o700)
        for n in names { #expect(perms(dir.appendingPathComponent(n)) == 0o600) }
        let vals = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(vals.isExcludedFromBackup == true)
    }

    @Test func writeFailureDoesNotThrow() throws {
        let file = tmp(); try Data().write(to: file); defer { try? FileManager.default.removeItem(at: file) }
        let store = QuestionAudioStore(directory: file.appendingPathComponent("sub"))   // родитель — файл
        #expect(store.save(samples: [0], turn: 1, sessionStart: start, sidecar: sidecar()) == nil)
    }

    @Test func purgeDeletesOnlyOldFiles() throws {
        let dir = tmp(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = QuestionAudioStore(directory: dir, now: { Date() })
        store.save(samples: [0.1], turn: 1, sessionStart: start, sidecar: sidecar())
        store.save(samples: [0.1], turn: 2, sessionStart: start, sidecar: sidecar())
        let old = Date().addingTimeInterval(-20 * 86_400)
        for n in ["-1.wav", "-1.json"] {
            let f = try FileManager.default.contentsOfDirectory(atPath: dir.path).first { $0.hasSuffix(n) }!
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: dir.appendingPathComponent(f).path)
        }
        #expect(store.purge(olderThanDays: 14) == 2)
        #expect(store.stats().count == 1)
        let future = QuestionAudioStore(directory: dir, now: { Date().addingTimeInterval(30 * 86_400) })
        #expect(future.purge(olderThanDays: 14) == 2)
        #expect(store.stats() == (0, 0))
    }

    @Test func deleteAllAndStats() throws {
        let dir = tmp(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = QuestionAudioStore(directory: dir)
        store.save(samples: [Float](repeating: 0, count: 100), turn: 1, sessionStart: start, sidecar: sidecar())
        try Data([1]).write(to: dir.appendingPathComponent("broken.bin"))
        let st = store.stats()
        #expect(st.count == 1 && st.bytes > 244)
        store.deleteAll()
        #expect(!FileManager.default.fileExists(atPath: dir.path))
        #expect(store.stats() == (0, 0))
    }

    @Test func settingsDefaultsAndClamp() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(s.saveQuestionAudio == false && s.questionAudioRetentionDays == 14)
        var t = AppSettings(); t.questionAudioRetentionDays = 500
        #expect(t.normalized().questionAudioRetentionDays == 90)
        t.questionAudioRetentionDays = 0
        #expect(t.normalized().questionAudioRetentionDays == 1)
    }
}
