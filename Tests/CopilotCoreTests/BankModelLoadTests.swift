import CopilotCore
import CopilotEmbeddings
import Foundation
import Synchronization
import Testing
@testable import InterviewCopilot

@MainActor
struct BankModelLoadTests {
    private final class StubEmbedder: TextEmbedder {
        let identifier: String
        let onRelease: @Sendable () -> Void
        init(_ file: String, onRelease: @escaping @Sendable () -> Void = {}) {
            identifier = file
            self.onRelease = onRelease
        }
        deinit { onRelease() }

        func embed(_ texts: [String]) throws -> [[Float]] {
            texts.map { _ in identifier == "second" ? [0, 1] : [1, 0] }
        }
    }

    private struct Timeout: Error {}

    /// Stop inside native model creation while the main actor continues to accept profile and settings changes.
    private final class LoadGate: Sendable {
        private let entered = Mutex(false)
        private let release = DispatchSemaphore(value: 0)

        var started: Bool { entered.withLock { $0 } }
        func open() { release.signal() }
        func wait() throws {
            #expect(!Thread.isMainThread)
            entered.withLock { $0 = true }
            guard release.wait(timeout: .now() + 10) == .success else { throw Timeout() }
        }
    }

    private func until(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while !condition() {
            guard clock.now < deadline else { throw Timeout() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func switchProfileDuringLoad() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = LoadGate()
        let library = ProfileLibrary(root: root.appendingPathComponent("profiles"))
        let bank = BankController(library: library, cacheDirectory: root.appendingPathComponent("cache")) { file in
            try gate.wait()
            return StubEmbedder(file)
        }
        defer { gate.open(); bank.shutdown() }
        let a = try #require(bank.createProfile(name: "A"))
        let b = try #require(bank.createProfile(name: "B"))
        for id in [a.id, b.id] {
            let cards = [BankCard(id: id, questions: ["Question \(id)?"], answer: "Synthetic answer")]
            try QuestionBankWriter.yaml(cards).write(to: library.questionsURL(id), atomically: true, encoding: .utf8)
            let dir = library.materialsDirectory(id)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "Synthetic material for \(id).".write(to: dir.appendingPathComponent("\(id).txt.md"), atomically: true, encoding: .utf8)
        }
        bank.select(a.id)
        bank.embeddingModelChanged("first")
        try await until { gate.started }
        bank.select(b.id)
        #expect(bank.cards.map(\.id) == [b.id])
        #expect(bank.embedFunction == nil)
        #expect(bank.materialIndex.entries.isEmpty)
        gate.open()
        try await until { bank.materialIndex.entries.count == 1 && bank.status == L("База: %@ карточек", "1") }
        let result = await bank.lookup("Question?", threshold: 0.9)
        #expect(result.match?.top.map(\.card.id) == [b.id])
        #expect(result.materials.map(\.source) == ["\(b.id).txt"])
        #expect(!FileManager.default.fileExists(atPath: library.materialsCacheURL(a.id).path))
    }

    @Test(arguments: [false, true])
    func supersededLoadCannotPublish(fails: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = LoadGate()
        let second = LoadGate()
        let bank = BankController(library: ProfileLibrary(root: root), cacheDirectory: root) { file in
            if file == "first" {
                try first.wait()
                if fails { throw EmbedderError.loadFailed(file) }
            } else {
                try second.wait()
            }
            return StubEmbedder(file)
        }
        defer { first.open(); second.open(); bank.shutdown() }
        bank.embeddingModelChanged("first")
        try await until { first.started }
        bank.embeddingModelChanged("second")
        first.open()
        try await until { second.started }
        #expect(bank.embedFunction == nil)
        #expect(bank.status == L("Загружаю модель…"))
        second.open()
        try await until { bank.embedFunction != nil }
        #expect(bank.embedFunction?("query") == [0, 1])
    }

    @Test func shutdownReleasesInFlightModel() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = LoadGate()
        let released = Mutex(false)
        let bank = BankController(library: ProfileLibrary(root: root), cacheDirectory: root) { file in
            try gate.wait()
            return StubEmbedder(file) { released.withLock { $0 = true } }
        }
        bank.embeddingModelChanged("first")
        try await until { gate.started }
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(20)) { gate.open() }
        bank.shutdown()
        #expect(released.withLock { $0 })
        #expect(bank.embedFunction == nil)
    }

    @Test func retryDuringFailedLoad() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let attempts = Mutex(0)
        let gate = LoadGate()
        let bank = BankController(library: ProfileLibrary(root: root), cacheDirectory: root) { file in
            if attempts.withLock({ $0 += 1; return $0 }) == 1 {
                try gate.wait()
                throw EmbedderError.modelNotFound(file)
            }
            return StubEmbedder(file)
        }
        defer { gate.open(); bank.shutdown() }
        bank.embeddingModelChanged("first")
        try await until { gate.started }
        bank.retryEmbedderIfMissing()
        gate.open()
        try await until { bank.embedFunction != nil }
        #expect(attempts.withLock { $0 } == 2)
    }
}
