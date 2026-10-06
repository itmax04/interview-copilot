import Foundation

/// Хранение настроек: JSON в UserDefaults (plan.md P-02). Ключи API здесь не хранятся — только Keychain (R-23).
public final class SettingsStore: @unchecked Sendable {
    public static let defaultsKey = "settings.v1"
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppSettings {
        lock.lock(); defer { lock.unlock() }
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings.migrated().normalized()
    }

    @discardableResult
    public func save(_ settings: AppSettings) -> AppSettings {
        let normalized = settings.normalized()
        lock.lock(); defer { lock.unlock() }
        if let data = try? JSONEncoder().encode(normalized) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
        return normalized
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}
