import Foundation
import Testing
@testable import CopilotCore

/// Работает с настоящей Связкой ключей, но в отдельном тестовом service; всё удаляется после теста.
@Suite("KeychainStore — R-23", .serialized)
struct KeychainStoreTests {
    private func withStore(_ body: (KeychainStore) throws -> Void) rethrows {
        let store = KeychainStore(service: "com.itmax04.interviewcopilot.tests.\(UUID().uuidString)")
        defer { for p in ProviderID.allCases { try? store.delete(p) } }
        try body(store)
    }

    // Синтетические значения, не похожие на реальные ключи (secret-scan.sh).
    private let fakeA = "test-value-alpha"
    private let fakeB = "test-value-beta"

    @Test func setGetDelete() throws {
        try withStore { store in
            #expect(store.contains(.gemini) == false)
            #expect(try store.get(.gemini) == nil)
            try store.set(fakeA, for: .gemini)
            #expect(store.contains(.gemini))
            #expect(try store.get(.gemini) == fakeA)
            #expect(store.contains(.deepseek) == false)
            try store.delete(.gemini)
            #expect(store.contains(.gemini) == false)
            #expect(try store.get(.gemini) == nil)
        }
    }

    @Test func overwriteAndTrim() throws {
        try withStore { store in
            try store.set(fakeA, for: .anthropic)
            try store.set("  \(fakeB)\n", for: .anthropic)
            #expect(try store.get(.anthropic) == fakeB)
        }
    }

    @Test func emptyValueRejected() throws {
        try withStore { store in
            #expect(throws: SecretStoreError.emptyValue) { try store.set("   ", for: .deepseek) }
            #expect(store.contains(.deepseek) == false)
        }
    }

    @Test func deleteMissingIsNoop() throws {
        try withStore { store in
            try store.delete(.deepseek)
        }
    }

    @Test func servicesAreIsolated() throws {
        try withStore { a in
            try withStore { b in
                try a.set(fakeA, for: .gemini)
                #expect(b.contains(.gemini) == false)
            }
        }
    }
}
