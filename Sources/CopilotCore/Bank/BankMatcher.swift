import CryptoKit
import Foundation

/// Совпадение карточки с ходом.
public struct CardScore: Equatable, Sendable {
    public var card: BankCard
    public var score: Double
}

/// Результат поиска по базе — R-07.
public struct BankMatch: Equatable, Sendable {
    /// Лучшая карточка, если score ≥ порога.
    public var matched: CardScore?
    /// Три ближайшие карточки (для «Нет в базе», S-02, и как основа для генерации, R-11).
    public var top: [CardScore]
}

/// Индекс базы: эмбеддинги всех формулировок всех карточек. Поиск локальный, без сети (R-07).
public struct BankIndex: Sendable {
    public let cards: [BankCard]
    /// (номер карточки, вектор формулировки)
    let vectors: [(Int, [Float])]

    public init(cards: [BankCard], vectors: [(Int, [Float])]) {
        self.cards = cards
        self.vectors = vectors
    }

    /// Сходство ход ↔ каждая формулировка, максимум по карточке; совпадение при score ≥ threshold.
    public func match(_ query: [Float], threshold: Double) -> BankMatch {
        var best = [Double](repeating: -1, count: cards.count)
        for (index, vector) in vectors {
            best[index] = max(best[index], Double(query.dot(vector)))
        }
        let ranked = best.enumerated().sorted { $0.element > $1.element }
            .filter { $0.element > -1 }
            .map { CardScore(card: cards[$0.offset], score: $0.element) }
        let top = Array(ranked.prefix(3))
        let matched = top.first.flatMap { $0.score >= threshold ? $0 : nil }
        return BankMatch(matched: matched, top: top)
    }
}

/// Строит индекс с кэшем эмбеддингов на диске (`…/cache/`): пересчитываются только новые формулировки (ADR-0001 п. 6).
public final class BankIndexBuilder: @unchecked Sendable {
    private let embedder: TextEmbedder
    private let cacheURL: URL?
    private var cache: [String: [Float]] = [:]
    private let lock = NSLock()

    public init(embedder: TextEmbedder, cacheDirectory: URL?) {
        self.embedder = embedder
        if let dir = cacheDirectory {
            let name = embedder.identifier.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
            cacheURL = dir.appendingPathComponent("embeddings-\(name).json")
        } else {
            cacheURL = nil
        }
        loadCache()
    }

    static func key(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func loadCache() {
        guard let url = cacheURL, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [Float]].self, from: data) else { return }
        cache = decoded
    }

    private func saveCache() {
        guard let url = cacheURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(cache) { try? data.write(to: url, options: .atomic) }
    }

    public func build(_ cards: [BankCard]) throws -> BankIndex {
        lock.lock()
        defer { lock.unlock() }
        var vectors: [(Int, [Float])] = []
        var missing: [String] = []
        for card in cards { for q in card.questions where cache[Self.key(q)] == nil { missing.append(q) } }
        if !missing.isEmpty {
            let unique = Array(Set(missing))
            let embedded = try embedder.embed(unique)
            for (q, v) in zip(unique, embedded) { cache[Self.key(q)] = v }
            saveCache()
        }
        for (i, card) in cards.enumerated() {
            for q in card.questions { if let v = cache[Self.key(q)] { vectors.append((i, v)) } }
        }
        return BankIndex(cards: cards, vectors: vectors)
    }

    public func embedQuery(_ text: String) throws -> [Float] {
        try embedder.embed([text])[0]
    }
}
