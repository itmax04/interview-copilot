import Foundation
import Security

/// Хранилище ключей API — R-23. Значение ключа никогда не логируется и не возвращается в UI после сохранения.
public protocol SecretStore: Sendable {
    func set(_ value: String, for provider: ProviderID) throws
    func get(_ provider: ProviderID) throws -> String?
    func delete(_ provider: ProviderID) throws
    func contains(_ provider: ProviderID) -> Bool
}

public enum SecretStoreError: Error, Equatable, CustomStringConvertible {
    case emptyValue
    case keychain(OSStatus)

    public var description: String {
        switch self {
        case .emptyValue:
            return "Пустой ключ"
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

    private func baseQuery(_ provider: ProviderID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
    }

    public func set(_ value: String, for provider: ProviderID) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SecretStoreError.emptyValue }
        let data = Data(trimmed.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(baseQuery(provider) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(provider)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            add[kSecAttrLabel as String] = "Interview Copilot — \(provider.displayName) API key"
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status) }
    }

    public func get(_ provider: ProviderID) throws -> String? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw SecretStoreError.keychain(status) }
        return String(data: data, encoding: .utf8)
    }

    public func delete(_ provider: ProviderID) throws {
        let status = SecItemDelete(baseQuery(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecretStoreError.keychain(status) }
    }

    /// Есть ли ключ — без чтения значения.
    public func contains(_ provider: ProviderID) -> Bool {
        var query = baseQuery(provider)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}

/// Хранилище в памяти для тестов и превью.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var values: [ProviderID: String] = [:]
    private let lock = NSLock()

    public init(_ initial: [ProviderID: String] = [:]) { values = initial }

    public func set(_ value: String, for provider: ProviderID) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SecretStoreError.emptyValue }
        lock.lock(); values[provider] = trimmed; lock.unlock()
    }

    public func get(_ provider: ProviderID) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[provider]
    }

    public func delete(_ provider: ProviderID) throws {
        lock.lock(); values[provider] = nil; lock.unlock()
    }

    public func contains(_ provider: ProviderID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return values[provider] != nil
    }
}
