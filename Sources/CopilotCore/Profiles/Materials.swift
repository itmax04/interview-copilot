import CryptoKit
import Foundation

/// Материал профиля — COPILOT-08 R-06: извлечённый текст загруженного файла (`materials/<имя файла>.md`).
public struct MaterialFile: Equatable, Hashable, Sendable, Identifiable {
    /// Имя исходного файла («swift-notes.pdf») — и подпись, и ключ.
    public var name: String
    public var characters: Int
    public var id: String { name }

    public init(name: String, characters: Int) {
        self.name = name
        self.characters = characters
    }
}

/// Фрагмент материала, похожий на вопрос.
public struct MaterialHit: Equatable, Sendable {
    public var source: String
    public var text: String
    public var score: Double

    public init(source: String, text: String, score: Double) {
        self.source = source
        self.text = text
        self.score = score
    }
}

/// Нарезка текста на фрагменты по абзацам: короткие куски (заголовки, строки списка) склеиваются до ~200 символов (не больше 800), длинный абзац —
/// по предложениям, длинное предложение — по словам. Абзац ≈ одна тема: eval `materials` — склейка до 800 смешивала темы
/// соседних абзацев (8 фрагментов на корпус, точность ниже).
public enum MaterialChunker {
    public static let maxCharacters = 800
    static let targetCharacters = 200
    /// Совсем короткие обрывки (номер страницы, заголовок без текста) не индексируются отдельно — присоединяются к соседу.
    static let minCharacters = 40

    public static func chunks(_ text: String, maxCharacters: Int = maxCharacters) -> [String] {
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var pieces: [String] = []
        for p in paragraphs {
            if p.count <= maxCharacters { pieces.append(p) } else { pieces += split(p, maxCharacters) }
        }
        var out: [String] = []
        var current = ""
        for piece in pieces {
            if current.isEmpty {
                current = piece
            } else if current.count < targetCharacters, current.count + 1 + piece.count <= maxCharacters {
                current += "\n" + piece
            } else {
                out.append(current)
                current = piece
            }
        }
        if !current.isEmpty {
            if current.count < minCharacters, let last = out.last, last.count + 1 + current.count <= maxCharacters * 5 / 4 {
                out[out.count - 1] = last + "\n" + current
            } else {
                out.append(current)
            }
        }
        return out
    }

    /// Длинный абзац: по предложениям, а предложение длиннее лимита — по словам.
    static func split(_ paragraph: String, _ limit: Int) -> [String] {
        var sentences: [String] = []
        paragraph.enumerateSubstrings(in: paragraph.startIndex..., options: .bySentences) { s, _, _, _ in
            if let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty { sentences.append(s) }
        }
        if sentences.isEmpty { sentences = [paragraph] }
        var out: [String] = []
        var current = ""
        func push(_ s: String) {
            if current.isEmpty { current = s } else if current.count + 1 + s.count <= limit { current += " " + s } else { out.append(current); current = s }
        }
        for s in sentences {
            if s.count <= limit { push(s); continue }
            for word in s.split(separator: " ").map(String.init) {
                push(word.count <= limit ? word : String(word.prefix(limit)))
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}

/// Индекс фрагментов профиля: поиск локальный (bge-m3), без сети.
public struct MaterialIndex: Sendable {
    public struct Entry: Sendable {
        public var source: String
        public var text: String
        public var vector: [Float]
    }

    public let entries: [Entry]
    public init(entries: [Entry]) { self.entries = entries }
    public static let empty = MaterialIndex(entries: [])

    /// Сходство вопроса и фрагмента bge-m3 ниже, чем вопроса и вопроса. Eval `materials` (2026-10-24, 16 фрагментов,
    /// 24 вопроса по теме uk/ru/en + 8 не по теме): 0,45 — 24/24 и лишнее 4/8; **0,47 — 23/24 и 2/8**; 0,50 — 21/24 и 2/8.
    public static let minScore = 0.47
    public static let limit = 4
    /// Не больше этого текста фрагментов в запросе (~900 токенов).
    public static let maxCharacters = 3_200

    public func search(_ query: [Float], limit: Int = MaterialIndex.limit, minScore: Double = MaterialIndex.minScore) -> [MaterialHit] {
        let ranked = entries.map { (entry: $0, score: Double(query.dot($0.vector))) }
            .filter { $0.score >= minScore }
            .sorted { $0.score > $1.score }
        var out: [MaterialHit] = []
        var total = 0
        for r in ranked {
            guard out.count < limit, total + r.entry.text.count <= Self.maxCharacters || out.isEmpty else { break }
            out.append(MaterialHit(source: r.entry.source, text: r.entry.text, score: r.score))
            total += r.entry.text.count
        }
        return out
    }
}

/// Строит индекс с кэшем векторов на диске (бинарный plist по хэшу фрагмента): пересчитываются только новые фрагменты.
/// Кэш — свой у каждого профиля, удаляется вместе с ним.
public final class MaterialIndexBuilder: @unchecked Sendable {
    private let embedder: TextEmbedder
    private let cacheURL: URL?
    private var cache: [String: Data] = [:]
    private let lock = NSLock()
    /// Эмбеддинги — пачками: прогресс и отмена между пачками.
    static let batch = 8   // мелкие пачки: поиск на интервью не ждёт индексацию дольше ~0,4 с

    public init(embedder: TextEmbedder, cacheURL: URL?) {
        self.embedder = embedder
        self.cacheURL = cacheURL
        if let cacheURL, let data = try? Data(contentsOf: cacheURL),
           let decoded = try? PropertyListDecoder().decode([String: Data].self, from: data) {
            cache = decoded
        }
    }

    func key(_ text: String) -> String {
        SHA256.hash(data: Data((embedder.identifier + "\n" + text).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// `files` — (имя источника, текст). `progress(готово, всего)`; `isCancelled` — прервать между пачками.
    public func build(_ files: [(source: String, text: String)], progress: (Int, Int) -> Void = { _, _ in },
                      isCancelled: () -> Bool = { false }) throws -> MaterialIndex {
        lock.lock()
        defer { lock.unlock() }
        let pieces = files.flatMap { f in MaterialChunker.chunks(f.text).map { (source: f.source, text: $0) } }
        let missing = Array(Set(pieces.map(\.text).filter { cache[key($0)] == nil }))
        var done = 0
        progress(0, missing.count)
        for start in stride(from: 0, to: missing.count, by: Self.batch) {
            if isCancelled() { throw CancellationError() }
            let slice = Array(missing[start..<min(start + Self.batch, missing.count)])
            for (text, vector) in zip(slice, try embedder.embed(slice)) { cache[key(text)] = Self.pack(vector) }
            done += slice.count
            progress(done, missing.count)
        }
        // Векторы удалённых фрагментов из кэша убираются: кэш не растёт бесконечно.
        let live = Set(pieces.map { key($0.text) })
        cache = cache.filter { live.contains($0.key) }
        if let cacheURL {
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            if let data = try? encoder.encode(cache) {
                try? data.write(to: cacheURL, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
            }
        }
        return MaterialIndex(entries: pieces.compactMap { p in
            cache[key(p.text)].map { MaterialIndex.Entry(source: p.source, text: p.text, vector: Self.unpack($0)) }
        })
    }

    static func pack(_ v: [Float]) -> Data { v.withUnsafeBufferPointer { Data(buffer: $0) } }
    static func unpack(_ d: Data) -> [Float] {
        d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
