import CryptoKit
import Foundation

/// Модель из `models.sha256` (R-22).
public struct ModelFile: Sendable, Equatable {
    public var sha256: String
    public var file: String
    public var size: Int64
    public var url: URL

    /// Разбор `models.sha256`: `<sha256>  <файл>  <размер>  <URL>`, строки с # — комментарии.
    public static func parseList(_ text: String) -> [ModelFile] {
        text.split(separator: "\n").compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("#") else { return nil }
            let parts = t.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 4, let size = Int64(parts[2]), let url = URL(string: parts[3]) else { return nil }
            return ModelFile(sha256: parts[0].lowercased(), file: parts[1], size: size, url: url)
        }
    }
}

public enum ModelDownloadError: Error, CustomStringConvertible, Equatable {
    case checksumMismatch(String)
    case http(Int)
    case notInList(String)

    public var description: String {
        switch self {
        case .checksumMismatch(let f): L10n.f("SHA256 не совпадает для %@: файл удалён", f)
        case .http(let s): L10n.f("HTTP %lld при загрузке", s)
        case .notInList(let f): L10n.f("%@ нет в списке моделей", f)
        }
    }
}

/// Загрузка моделей в `…/models/` с проверкой SHA256: при несовпадении файл удаляется и показывается ошибка (R-22).
public final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public let directory: URL
    public let list: [ModelFile]
    private var progressHandler: (@Sendable (Double) -> Void)?
    private var continuation: CheckedContinuation<URL, Error>?
    private let lock = NSLock()

    public init(directory: URL, list: [ModelFile]) {
        self.directory = directory
        self.list = list
    }

    public func entry(_ file: String) -> ModelFile? { list.first { $0.file == file } }

    public func isPresent(_ file: String) -> Bool {
        guard let e = entry(file) else { return FileManager.default.fileExists(atPath: directory.appendingPathComponent(file).path) }
        let path = directory.appendingPathComponent(file).path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return false }
        return (attrs[.size] as? NSNumber)?.int64Value == e.size
    }

    /// SHA256 файла потоково (модели — сотни МБ).
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Проверить уже скачанный файл; при несовпадении удалить.
    public func verify(_ file: String) throws {
        guard let e = entry(file) else { throw ModelDownloadError.notInList(file) }
        let url = directory.appendingPathComponent(file)
        if try Self.sha256(of: url) != e.sha256 {
            try? FileManager.default.removeItem(at: url)
            throw ModelDownloadError.checksumMismatch(file)
        }
    }

    public func download(_ file: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let e = entry(file) else { throw ModelDownloadError.notInList(file) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        lock.withLock { progressHandler = progress }
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let tmp = try await withCheckedThrowingContinuation { (c: CheckedContinuation<URL, Error>) in
            lock.withLock { continuation = c }
            session.downloadTask(with: e.url).resume()
        }
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard try Self.sha256(of: tmp) == e.sha256 else { throw ModelDownloadError.checksumMismatch(file) }
        let target = directory.appendingPathComponent(file)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: tmp, to: target)
    }

    // MARK: URLSessionDownloadDelegate

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let handler = lock.withLock { progressHandler }
        handler?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let c = lock.withLock { () -> CheckedContinuation<URL, Error>? in defer { continuation = nil }; return continuation }
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            c?.resume(throwing: ModelDownloadError.http(http.statusCode))
            return
        }
        // Файл во временной папке удаляется после возврата — переносим.
        let keep = FileManager.default.temporaryDirectory.appendingPathComponent("model-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: keep)
            c?.resume(returning: keep)
        } catch {
            c?.resume(throwing: error)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let c = lock.withLock { () -> CheckedContinuation<URL, Error>? in defer { continuation = nil }; return continuation }
        c?.resume(throwing: error)
    }
}
