import Foundation
import Yams

/// Профиль в списке (COPILOT-08 R-01): `id` — имя папки, `name` — из `profile.yaml`.
public struct ProfileInfo: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Текстовые разделы профиля, которые владелец загружает файлом или пишет сам.
public enum ProfileDocument: String, CaseIterable, Sendable, Identifiable {
    case resume, facts, job, instructions

    public var id: String { rawValue }

    public var fileName: String {
        switch self {
        case .resume: "resume.md"
        case .facts: "stories.md"
        case .job: "job.md"
        case .instructions: "instructions.md"
        }
    }

    public var title: String {
        switch self {
        case .resume: "Резюме"
        case .facts: "Факты о себе"
        case .job: "Вакансия"
        case .instructions: "Инструкции профиля"
        }
    }
}

/// Что стало со старой папкой `profile/` (до COPILOT-08).
public enum LegacyProfileMigration: Equatable, Sendable {
    case none
    /// Папка совпадала с вымышленным примером — удалена (решение владельца Q12).
    case removedExample
    /// Папка с данными владельца перенесена в профиль.
    case moved(ProfileInfo)
}

/// Профили владельца на диске — COPILOT-08 R-01: `profiles/<id>/` с правами 700/600, только локально.
public final class ProfileLibrary: @unchecked Sendable {
    public let root: URL
    private let lock = NSLock()
    private let fm = FileManager.default

    public init(root: URL = AppPaths.profiles) {
        self.root = root
    }

    public static let defaultName = "Мой профиль"
    /// Шапка нового `questions.yaml`: пустой список — тоже правильная база.
    static let emptyQuestions = "# Вопросы профиля (COPILOT-08 R-07). Формат: - id: …, questions: [...], answer: |\n[]\n"

    public func directory(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
    public func questionsURL(_ id: String) -> URL { directory(id).appendingPathComponent("questions.yaml") }
    public func sourcesDirectory(_ id: String) -> URL { directory(id).appendingPathComponent("sources", isDirectory: true) }

    /// Профили по имени.
    public func list() -> [ProfileInfo] {
        lock.withLock {
            let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            return dirs.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .filter { fm.fileExists(atPath: $0.appendingPathComponent("profile.yaml").path) }
                .map { ProfileInfo(id: $0.lastPathComponent, name: Self.readName(in: $0) ?? $0.lastPathComponent) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    public func exists(_ id: String) -> Bool { list().contains { $0.id == id } }

    @discardableResult
    public func create(name: String) throws -> ProfileInfo {
        let name = Self.cleanName(name)
        return try lock.withLock {
            try ensureRoot()
            let base = Self.slug(name)
            var id = base
            var n = 2
            while fm.fileExists(atPath: directory(id).path) {
                id = "\(base)-\(n)"
                n += 1
            }
            try fm.createDirectory(at: directory(id), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try writeYAML(name: name, language: nil, in: directory(id))
            for doc in ProfileDocument.allCases { try writeFile("", to: directory(id).appendingPathComponent(doc.fileName)) }
            try writeFile(Self.emptyQuestions, to: questionsURL(id))
            return ProfileInfo(id: id, name: name)
        }
    }

    public func rename(_ id: String, to name: String) throws {
        let dir = directory(id)
        let language = ProfileStore.load(from: dir).defaultLanguage
        try lock.withLock { try writeYAML(name: Self.cleanName(name), language: language, in: dir) }
    }

    public func delete(_ id: String) throws {
        try lock.withLock {
            let dir = directory(id)
            if fm.fileExists(atPath: dir.path) { try fm.removeItem(at: dir) }
        }
    }

    public func load(_ id: String) -> Profile { ProfileStore.load(from: directory(id)) }

    public func read(_ doc: ProfileDocument, of id: String) -> String {
        (try? String(contentsOf: directory(id).appendingPathComponent(doc.fileName), encoding: .utf8)) ?? ""
    }

    public func write(_ text: String, _ doc: ProfileDocument, of id: String) throws {
        try lock.withLock { try writeFile(text, to: directory(id).appendingPathComponent(doc.fileName)) }
    }

    /// Загрузка файла в раздел (R-02): текст извлекается и сохраняется в `.md`, исходник — в `sources/`. Возвращает текст.
    @discardableResult
    public func importFile(_ url: URL, as doc: ProfileDocument, into id: String) throws -> String {
        let text = try DocumentText.extract(from: url)
        try lock.withLock {
            let sources = sourcesDirectory(id)
            try fm.createDirectory(at: sources, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let copy = sources.appendingPathComponent("\(doc.rawValue).\(url.pathExtension.lowercased())")
            if fm.fileExists(atPath: copy.path) { try fm.removeItem(at: copy) }
            try Data(contentsOf: url).write(to: copy, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: copy.path)
            try writeFile(text, to: directory(id).appendingPathComponent(doc.fileName))
        }
        return text
    }

    // MARK: Общие инструкции

    public static func readGeneralInstructions(at url: URL = AppPaths.generalInstructions) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    public static func writeGeneralInstructions(_ text: String, at url: URL = AppPaths.generalInstructions) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // MARK: Старая папка `profile/`

    /// Старая папка: совпадает с примером (все файлы примера на месте и не изменены, лишних нет) — удаляется;
    /// иначе переносится в новый профиль. После этого старой папки нет.
    public func migrateLegacy(_ legacy: URL, example: URL?) throws -> LegacyProfileMigration {
        guard fm.fileExists(atPath: legacy.path) else { return .none }
        if let example, Self.isUnchangedExample(legacy, example: example) {
            try fm.removeItem(at: legacy)
            return .removedExample
        }
        let name = ProfileStore.load(from: legacy).name
        let info = try create(name: name == "Profile" ? Self.defaultName : name)
        try lock.withLock {
            let dir = directory(info.id)
            let files = (try? fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.lastPathComponent != ".DS_Store" {
                let target = dir.appendingPathComponent(file.lastPathComponent)
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.moveItem(at: file, to: target)
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            }
            try fm.removeItem(at: legacy)
        }
        return .moved(info)
    }

    static func isUnchangedExample(_ dir: URL, example: URL) -> Bool {
        let fm = FileManager.default
        let ignored: Set<String> = [".DS_Store"]
        let mine = Set(((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { !ignored.contains($0) })
        let theirs = Set(((try? fm.contentsOfDirectory(atPath: example.path)) ?? []).filter { !ignored.contains($0) })
        guard !theirs.isEmpty, mine.isSubset(of: theirs) else { return false }
        return mine.allSatisfy { f in
            fm.contentsEqual(atPath: dir.appendingPathComponent(f).path, andPath: example.appendingPathComponent(f).path)
        }
    }

    // MARK: Внутреннее

    private func ensureRoot() throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    private func writeFile(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func writeYAML(name: String, language: String?, in dir: URL) throws {
        var map: [String: String] = ["name": name]
        if let language { map["default_language"] = language }
        try writeFile(try Yams.dump(object: map), to: dir.appendingPathComponent("profile.yaml"))
    }

    static func readName(in dir: URL) -> String? {
        guard let text = try? String(contentsOf: dir.appendingPathComponent("profile.yaml"), encoding: .utf8),
              let yaml = try? Yams.load(yaml: text) as? [String: Any], let name = yaml["name"] as? String, !name.isEmpty else { return nil }
        return name
    }

    static func cleanName(_ name: String) -> String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? defaultName : String(t.prefix(80))
    }

    /// Имя папки: латиница, цифры и дефис; кириллица транслитерируется, иначе — «profile».
    static func slug(_ name: String) -> String {
        let latin = name.applyingTransform(.toLatin, reverse: false)?.applyingTransform(.stripDiacritics, reverse: false) ?? name
        var out = ""
        for ch in latin.lowercased() {
            if ch.isASCII, ch.isLetter || ch.isNumber { out.append(ch) } else if out.last != "-" { out.append("-") }
        }
        let trimmed = String(out.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(40))
        return trimmed.isEmpty ? "profile" : trimmed
    }
}
