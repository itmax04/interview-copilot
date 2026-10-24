import Foundation
import Yams

/// Профиль владельца — R-21, COPILOT-08 R-01: папка профиля (profile.yaml, resume.md, job.md, stories.md, instructions.md,
/// questions.yaml). Профилей несколько (`ProfileLibrary`). В Git не попадает (.gitignore, AC-06).
public struct Profile: Equatable, Sendable {
    public var name: String
    public var defaultLanguage: String?
    public var resume: String
    public var job: String
    /// «Факты о себе»: истории STAR, достижения, причины ухода, ожидания (COPILOT-08 Q4).
    public var stories: String
    /// Инструкции владельца для этого профиля (COPILOT-08 R-04) — указания модели, а не данные.
    public var instructions: String

    public init(name: String, defaultLanguage: String? = nil, resume: String = "", job: String = "", stories: String = "",
                instructions: String = "") {
        self.name = name
        self.defaultLanguage = defaultLanguage
        self.resume = resume
        self.job = job
        self.stories = stories
        self.instructions = instructions
    }
}

public enum ProfileStore {
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
        return Profile(name: name, defaultLanguage: lang, resume: read("resume.md"), job: read("job.md"), stories: read("stories.md"),
                       instructions: read("instructions.md"))
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
