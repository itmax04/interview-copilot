import Foundation
import Security

/// Хранилище ключей API — R-23. Значение ключа никогда не логируется и не возвращается в UI после сохранения.
/// Хранилище ключей. У провайдера сколько угодно ключей (COPILOT-09: несколько аккаунтов — когда у одного кончается
/// лимит, ответ идет со следующего). Слот 1 — основной ключ, как раньше.
public protocol SecretStore: Sendable {
    func set(_ value: String, for provider: ProviderID, slot: Int) throws
    func get(_ provider: ProviderID, slot: Int) throws -> String?
    func delete(_ provider: ProviderID, slot: Int) throws
    /// Имена всех сохраненных ключей (`groq`, `groq#2`…) — одним запросом, без чтения значений.
    func accounts() -> Set<String>
}

public enum KeySlots {
    /// Слот 1 — `groq` (как до COPILOT-09), остальные — `groq#2`, `groq#3`… без ограничения числа.
    public static func account(_ provider: ProviderID, _ slot: Int) -> String {
        slot <= 1 ? provider.rawValue : "\(provider.rawValue)#\(slot)"
    }

    /// Номер слота по имени ключа: `groq` → 1, `groq#7` → 7; чужой провайдер — nil.
    public static func slot(of account: String, provider: ProviderID) -> Int? {
        if account == provider.rawValue { return 1 }
        let prefix = provider.rawValue + "#"
        guard account.hasPrefix(prefix), let n = Int(account.dropFirst(prefix.count)), n >= 2 else { return nil }
        return n
    }
}

extension SecretStore {
    public func set(_ value: String, for provider: ProviderID) throws { try set(value, for: provider, slot: 1) }
    public func get(_ provider: ProviderID) throws -> String? { try get(provider, slot: 1) }
    public func delete(_ provider: ProviderID) throws { try delete(provider, slot: 1) }

    /// Слоты с ключом, по порядку.
    public func slots(_ provider: ProviderID, in accounts: Set<String>? = nil) -> [Int] {
        let all = accounts ?? self.accounts()
        return all.compactMap { KeySlots.slot(of: $0, provider: provider) }.sorted()
    }

    /// Есть ли у провайдера хоть один ключ — без чтения значений.
    public func contains(_ provider: ProviderID) -> Bool { !slots(provider).isEmpty }

    /// Все ключи провайдера по порядку слотов (пустые и нечитаемые пропускаются).
    public func keys(_ provider: ProviderID, in accounts: Set<String>? = nil) -> [(slot: Int, key: String)] {
        slots(provider, in: accounts).compactMap { slot in
            guard let key = try? get(provider, slot: slot), !key.isEmpty else { return nil }
            return (slot, key)
        }
    }

    /// Слот для нового дополнительного ключа: первый свободный начиная с 2.
    public func freeExtraSlot(_ provider: ProviderID) -> Int {
        let used = Set(slots(provider))
        var n = 2
        while used.contains(n) { n += 1 }
        return n
    }

    /// Номера без пропусков после удаления (1, 2, 3…): «Ключ 3» в настройках и в причине ошибки — один и тот же ключ.
    public func compactSlots(_ provider: ProviderID) throws {
        for (index, slot) in slots(provider).enumerated() where slot != index + 1 {
            guard let value = try get(provider, slot: slot) else { continue }
            try set(value, for: provider, slot: index + 1)
            try delete(provider, slot: slot)
        }
    }
}

public enum SecretStoreError: Error, Equatable, CustomStringConvertible {
    case emptyValue
    case keychain(OSStatus)

    public var description: String {
        switch self {
        case .emptyValue:
            return L10n.t("Пустой ключ")
        case .keychain(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Keychain: \(message)"
        }
    }
}

/// Связка ключей macOS: `kSecClassGenericPassword`, service из ADR-0001 п. 8, account = провайдер.
public struct KeychainStore: SecretStore {
    public static let defaultService = "com.itmax04.interviewcopilot"
    public let service: String

    public init(service: String = KeychainStore.defaultService) {
        self.service = service
    }

    private func baseQuery(_ provider: ProviderID, _ slot: Int) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: KeySlots.account(provider, slot),
        ]
    }

    public func set(_ value: String, for provider: ProviderID, slot: Int) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SecretStoreError.emptyValue }
        let data = Data(trimmed.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(baseQuery(provider, slot) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(provider, slot)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            add[kSecAttrLabel as String] = "Interview Copilot — \(provider.displayName) API key" + (slot > 1 ? " \(slot)" : "")
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status) }
    }

    public func get(_ provider: ProviderID, slot: Int) throws -> String? {
        var query = baseQuery(provider, slot)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw SecretStoreError.keychain(status) }
        return String(data: data, encoding: .utf8)
    }

    public func delete(_ provider: ProviderID, slot: Int) throws {
        let status = SecItemDelete(baseQuery(provider, slot) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecretStoreError.keychain(status) }
    }

    /// Все ключи приложения одним запросом атрибутов (без значений): цепочка собирается перед каждым ответом,
    /// и по запросу на каждый слот каждого провайдера было бы до 30 обращений к Связке ключей.
    public func accounts() -> Set<String> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
        return Set(items.compactMap { $0[kSecAttrAccount as String] as? String })
    }
}

/// Хранилище в памяти для тестов и превью.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    private let lock = NSLock()

    public init(_ initial: [ProviderID: String] = [:]) {
        for (p, v) in initial { values[KeySlots.account(p, 1)] = v }
    }

    public func set(_ value: String, for provider: ProviderID, slot: Int) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SecretStoreError.emptyValue }
        lock.withLock { values[KeySlots.account(provider, slot)] = trimmed }
    }

    public func get(_ provider: ProviderID, slot: Int) throws -> String? {
        lock.withLock { values[KeySlots.account(provider, slot)] }
    }

    public func delete(_ provider: ProviderID, slot: Int) throws {
        lock.withLock { values[KeySlots.account(provider, slot)] = nil }
    }

    public func accounts() -> Set<String> { lock.withLock { Set(values.keys) } }
}
