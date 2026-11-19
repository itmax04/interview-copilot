import CopilotCore
import Foundation
import Synchronization
import Testing
@testable import InterviewCopilot

@MainActor
struct QuestionPDFImportTests {
    @Test(arguments: [false, true])
    func switchProfileDuringPDFRead(returnToOriginal: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = ProfileLibrary(root: root)
        let bank = BankController(library: library, cacheDirectory: root.appendingPathComponent("cache"))
        defer { bank.shutdown() }
        let a = try #require(bank.createProfile(name: "First"))
        let b = try #require(bank.createProfile(name: "Second"))
        bank.select(a.id)
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(settingsStore: SettingsStore(defaults: defaults), secrets: InMemorySecretStore())
        let reading = Mutex(false)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let preparer = QuestionPreparer(bank: bank, model: model) { _ in
            #expect(!Thread.isMainThread)
            reading.withLock { $0 = true }
            guard release.wait(timeout: .now() + 10) == .success else { throw Timeout() }
            return "Q: Which path parses the file?\nQ: Which profile owns the result?"
        }

        let input = root.appendingPathComponent("synthetic.pdf")
        preparer.importFile(input)
        try await until { reading.withLock { $0 } }
        #expect(preparer.running)
        bank.select(b.id)
        if returnToOriginal { bank.select(a.id) }
        release.signal()
        try await until { !preparer.running }

        #expect(preparer.pendingImport == nil)
        #expect(preparer.failed)
        #expect(preparer.message == L("Профиль сменили — импорт остановлен."))
        #expect(try QuestionBankParser.load(library.questionsURL(a.id)).isEmpty)
        #expect(try QuestionBankParser.load(library.questionsURL(b.id)).isEmpty)
        #expect(bank.activeID == (returnToOriginal ? a.id : b.id))

        // The selected profile can immediately start another import and accept its own results.
        let active = try #require(bank.activeID)
        let other = active == a.id ? b.id : a.id
        release.signal()
        preparer.importFile(input)
        try await until { !preparer.running }
        let items = try #require(preparer.pendingImport)
        #expect(items.count == 2)
        bank.select(other)
        #expect(preparer.pendingImport == nil)
        bank.select(active)
        #expect(preparer.pendingImport == nil)
        preparer.acceptImport(items)
        #expect(try QuestionBankParser.load(library.questionsURL(active)).isEmpty)
        #expect(try QuestionBankParser.load(library.questionsURL(other)).isEmpty)

        release.signal()
        preparer.importFile(input)
        try await until { !preparer.running }
        preparer.acceptImport(try #require(preparer.pendingImport))
        #expect(try QuestionBankParser.load(library.questionsURL(active)).count == 2)
        #expect(try QuestionBankParser.load(library.questionsURL(other)).isEmpty)
    }

    private struct Timeout: Error {}

    private func until(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while !condition() {
            guard clock.now < deadline else { throw Timeout() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
