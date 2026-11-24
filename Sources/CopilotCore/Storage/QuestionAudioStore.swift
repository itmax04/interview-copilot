import Foundation

/// COPILOT-17 R-09/R-10: необязательное локальное сохранение звука вопросов собеседника (по умолчанию выключено).
/// Файлы: `<папка>/<начало сессии>-<ход>.wav` (16 кГц, 16 бит, моно) и `….json` только с числами —
/// ни текста вопроса, ни имён в файлах нет. Папка 700, файлы 600, исключены из резервных копий.
public final class QuestionAudioStore: @unchecked Sendable {
    /// Содержимое sidecar: только числа и коды (тест проверяет набор ключей).
    public struct Sidecar: Codable, Equatable, Sendable {
        public var durationSeconds: Double
        public var sampleRate: Int
        public var language: String
        public var channel: String
        public var decodeMs: Int
        public var whisperDecodeMs: Int?
        public var whisperTextDiffered: Bool?
        public init(durationSeconds: Double, sampleRate: Int = 16_000, language: String, channel: String = "call",
                    decodeMs: Int, whisperDecodeMs: Int? = nil, whisperTextDiffered: Bool? = nil) {
            self.durationSeconds = durationSeconds; self.sampleRate = sampleRate; self.language = language
            self.channel = channel; self.decodeMs = decodeMs
            self.whisperDecodeMs = whisperDecodeMs; self.whisperTextDiffered = whisperTextDiffered
        }
    }

    public let directory: URL
    /// Общая на все экземпляры: очистка и сохранение из разных мест не гоняются друг с другом.
    private static let sharedLock = NSLock()
    private var lock: NSLock { Self.sharedLock }
    private let now: @Sendable () -> Date

    public init(directory: URL = AppPaths.questionAudio, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.now = now
    }

    private static let nameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return f
    }()

    /// Записывает WAV и sidecar; возвращает размер в байтах или nil при ошибке (ошибка не пробрасывается).
    @discardableResult
    public func save(samples: [Float], turn: Int, sessionStart: Date, sidecar: Sidecar) -> Int? {
        lock.withLock {
            do {
                try ensureDirectory()
                let base = "\(Self.nameFormatter.string(from: sessionStart))-\(turn)"
                let wav = Self.wav(from: samples, sampleRate: sidecar.sampleRate)
                let wavURL = directory.appendingPathComponent(base + ".wav")
                try write(wav, to: wavURL)
                let enc = JSONEncoder()
                enc.outputFormatting = [.sortedKeys]
                try write(try enc.encode(sidecar), to: directory.appendingPathComponent(base + ".json"))
                return wav.count
            } catch {
                return nil
            }
        }
    }

    /// Удаляет файлы старше `days` суток (по дате изменения). Возвращает число удалённых файлов.
    @discardableResult
    public func purge(olderThanDays days: Int) -> Int {
        lock.withLock {
            let cutoff = now().addingTimeInterval(-Double(days) * 86_400)
            var removed = 0
            for f in files() {
                let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if date < cutoff, (try? FileManager.default.removeItem(at: f)) != nil { removed += 1 }
            }
            return removed
        }
    }

    /// Вся папка, включая нечитаемые файлы.
    public func deleteAll() {
        lock.withLock {
            guard FileManager.default.fileExists(atPath: directory.path) else { return }
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Число записей (WAV) и общий размер всех файлов папки.
    public func stats() -> (count: Int, bytes: Int) {
        lock.withLock {
            let all = files()
            let bytes = all.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            return (all.filter { $0.pathExtension == "wav" }.count, bytes)
        }
    }

    private func files() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
    }

    private func ensureDirectory() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var dir = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
    }

    private func write(_ data: Data, to url: URL) throws {
        // Сразу с правами 600, без окна с правами по умолчанию.
        guard FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var u = url
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? u.setResourceValues(values)
    }

    /// 16-бит PCM WAV, моно.
    static func wav(from samples: [Float], sampleRate: Int) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let dataBytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes)
        d.append(contentsOf: Array("WAVE".utf8)); d.append(contentsOf: Array("fmt ".utf8))
        u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataBytes)
        for s in samples { u16(UInt16(bitPattern: Int16((max(-1, min(1, s)) * 32767).rounded()))) }
        return d
    }
}
