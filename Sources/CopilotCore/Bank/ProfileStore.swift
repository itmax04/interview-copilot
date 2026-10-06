import Foundation
import Yams

/// Профиль владельца — R-21: `…/InterviewCopilot/profile/` (profile.yaml, resume.md, job.md, stories.md, questions.yaml).
/// При первом запуске копируется из `profile.example/`. В Git не попадает (.gitignore, AC-06).
public struct Profile: Equatable, Sendable {
    public var name: String
    public var defaultLanguage: String?
    public var resume: String
    public var job: String
    public var stories: String

    public init(name: String, defaultLanguage: String? = nil, resume: String = "", job: String = "", stories: String = "") {
        self.name = name
        self.defaultLanguage = defaultLanguage
        self.resume = resume
        self.job = job
        self.stories = stories
    }
}

public enum ProfileStore {
    public static let files = ["profile.yaml", "resume.md", "job.md", "stories.md", "questions.yaml"]

    /// Копирует недостающие файлы из примера (существующие файлы владельца не трогает).
    @discardableResult
    public static func ensureProfile(at dir: URL, example: URL?) throws -> [String] {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let example else { return [] }
        var copied: [String] = []
        for file in files {
            let target = dir.appendingPathComponent(file)
            let source = example.appendingPathComponent(file)
            if !fm.fileExists(atPath: target.path), fm.fileExists(atPath: source.path) {
                // Чтение и запись, а не copyItem: copyItem клонирует файл (clonefile), и если .app лежит в iCloud Drive,
                // клонирование зависает в File Provider (замер P-06: главный поток висел в clonefileat).
                try Data(contentsOf: source).write(to: target, options: .atomic)
                copied.append(file)
            }
        }
        return copied
    }

    public static func load(from dir: URL) -> Profile {
        func read(_ f: String) -> String {
            (try? String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)) ?? ""
        }
        var name = "Profile"
        var lang: String?
        if let yaml = try? Yams.load(yaml: read("profile.yaml")) as? [String: Any] {
            if let n = yaml["name"] as? String, !n.isEmpty { name = n }
            lang = yaml["default_language"] as? String
        }
        return Profile(name: name, defaultLanguage: lang, resume: read("resume.md"), job: read("job.md"), stories: read("stories.md"))
    }
}

/// Наблюдение за файлом: редакторы сохраняют через замену файла, поэтому после rename/delete наблюдение перевешивается.
public final class FileWatcher: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "com.itmax04.interviewcopilot.filewatch")
    private var source: DispatchSourceFileSystemObject?
    private let onChange: @Sendable () -> Void
    private var pending: DispatchWorkItem?

    public init(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    public func start() {
        queue.async { self.arm() }
    }

    public func stop() {
        queue.sync {
            source?.cancel()
            source = nil
        }
    }

    private func arm() {
        source?.cancel()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // Файла пока нет — пробуем позже.
            queue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.arm() }
            return
        }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: queue)
        s.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = s.data
            self.debounce()
            if flags.contains(.rename) || flags.contains(.delete) {
                self.queue.asyncAfter(deadline: .now() + 0.2) { self.arm() }
            }
        }
        s.setCancelHandler { close(fd) }
        source = s
        s.resume()
    }

    private func debounce() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        queue.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
