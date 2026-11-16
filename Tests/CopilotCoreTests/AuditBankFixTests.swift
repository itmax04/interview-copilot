import Foundation
import Testing
@testable import CopilotCore

/// Эмбеддер, который запоминает размер каждой пачки.
private final class BatchRecordingEmbedder: TextEmbedder, @unchecked Sendable {
    let identifier = "batch-recorder"
    private let lock = NSLock()
    private var sizes: [Int] = []
    var batchSizes: [Int] { lock.withLock { sizes } }

    func embed(_ texts: [String]) throws -> [[Float]] {
        lock.withLock { sizes.append(texts.count) }
        return texts.map { text in
            var v = [Float](repeating: 0, count: 32)
            for (i, scalar) in text.unicodeScalars.enumerated() { v[(Int(scalar.value) + i) % 32] += 1 }
            return v.normalized()
        }
    }
}

@Suite("COPILOT-13 — индекс базы считается пачками")
struct BankIndexBatchingTests {
    @Test("Пересчёт не занимает эмбеддер одним вызовом на всю базу")
    func buildEmbedsInSmallBatches() throws {
        let embedder = BatchRecordingEmbedder()
        let builder = BankIndexBuilder(embedder: embedder, cacheDirectory: nil)
        let cards = (0..<21).map { BankCard(id: "c\($0)", questions: ["Вопрос номер \($0) про тему \($0 * 7)"], answer: "ответ") }

        let index = try builder.build(cards)

        #expect(embedder.batchSizes.reduce(0, +) == 21)
        #expect(embedder.batchSizes.count == 3)
        #expect(embedder.batchSizes.allSatisfy { $0 <= BankIndexBuilder.batch })
        // Все формулировки попали в индекс: каждая карточка находится по своему вопросу.
        for card in cards {
            let query = try builder.embedQuery(card.questions[0])
            #expect(index.match(query, threshold: 0.99).matched?.card.id == card.id)
        }
    }

    @Test("Повторный пересчёт берёт векторы из кэша")
    func secondBuildUsesCache() throws {
        let embedder = BatchRecordingEmbedder()
        let builder = BankIndexBuilder(embedder: embedder, cacheDirectory: nil)
        let cards = (0..<10).map { BankCard(id: "c\($0)", questions: ["Формулировка \($0)"], answer: "ответ") }
        _ = try builder.build(cards)
        let before = embedder.batchSizes.count
        _ = try builder.build(cards)
        #expect(embedder.batchSizes.count == before)
    }
}

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func hit() { lock.withLock { value += 1 } }
}

@Suite("COPILOT-13 — остановленное наблюдение за файлом")
struct FileWatcherStopTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("copilot-watch-\(UUID().uuidString).yaml")
    }

    private func waitForCalls(_ counter: CallCounter, seconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if counter.count > 0 { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return counter.count > 0
    }

    @Test("Изменение файла вызывает onChange")
    func reportsChange() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("a".utf8).write(to: url)
        let counter = CallCounter()
        let watcher = FileWatcher(url: url) { counter.hit() }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(200))
        try Data("b".utf8).write(to: url, options: .atomic)
        #expect(await waitForCalls(counter, seconds: 5))
    }

    @Test("После stop() наблюдение не оживает, когда файл появляется")
    func stoppedWatcherStaysStopped() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let counter = CallCounter()
        let watcher = FileWatcher(url: url) { counter.hit() }
        watcher.start()   // файла ещё нет: наблюдение повторяет попытку раз в секунду
        try await Task.sleep(for: .milliseconds(100))
        watcher.stop()
        try Data("a".utf8).write(to: url)
        try await Task.sleep(for: .milliseconds(1_400))   // прежде здесь срабатывала отложенная попытка
        try Data("b".utf8).write(to: url)
        try await Task.sleep(for: .milliseconds(700))
        #expect(counter.count == 0)
    }
}
