import Foundation
import Testing
@testable import CopilotCore
@testable import InterviewCopilot

@MainActor
struct SessionLifecycleAuditTests {
    @Test(arguments: [false, true])
    func ownerOnlySessionPersistsUntilDeleted(deleteAll: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let sessions = SessionController(store: store)
        sessions.start(source: nil, retentionDays: 30)
        sessions.addOwnerUtterance("Synthetic utterance")
        sessions.saveNow()
        let id = try #require(sessions.current?.id)
        #expect(store.load(id)?.ownerUtterances.count == 1)
        if deleteAll { try sessions.deleteAll() } else { try sessions.delete(id) }
        sessions.addOwnerUtterance("Synthetic continuation")
        sessions.finish()
        #expect(store.list().isEmpty)

        sessions.start(source: nil, retentionDays: 30)
        sessions.addOwnerUtterance("Next call")
        sessions.finish()
        #expect(store.list().count == 1)
    }

    @Test func failedBulkDeletionStopsFurtherTranscriptWrites() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let sessions = SessionController(store: store)
        sessions.start(source: nil, retentionDays: 30)
        sessions.addOwnerUtterance("Synthetic")
        sessions.saveNow()
        let id = try #require(sessions.current?.id)
        try store.delete(id)
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory)
        #expect(throws: (any Error).self) { try sessions.deleteAll() }
        try FileManager.default.removeItem(at: directory)
        sessions.finish()
        #expect(store.load(id) == nil)
    }

    @Test func partialReviewPersistsAndResumes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        var record = store.newSession(source: nil)
        record.exchanges = (1...2).map { SessionExchange(id: $0, question: "Question", answer: ["Answer"], askedAt: Date()) }
        try store.save(record)
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let secrets = InMemorySecretStore()
        try secrets.set("synthetic", for: .groq)
        let model = AppModel(settingsStore: SettingsStore(defaults: defaults), secrets: secrets)
        model.settings.chain = [.groq]
        let provider = ScriptedProvider(id: .groq) { call in
            switch call {
            case 1: .reply([#"[{"id":1,"good":"First"}]"#])
            case 2: .reply([#"[{"id":2,"good":"Second"}]"#])
            default: .reply([#"{"overview":"Summary"}"#])
            }
        }
        let reviews = ReviewController(store: store, model: model, bank: BankController(), providers: [.groq: provider])
        for attempt in 1...2 {
            reviews.start(record.id)
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(5)
            while reviews.running.contains(record.id), clock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            let saved = try #require(store.load(record.id)?.review)
            #expect(saved.comments.count == attempt)
            if attempt == 1 {
                guard case .failed = saved.status else { Issue.record("Partial review must be retryable"); return }
                #expect(saved.summary == nil)
            } else {
                #expect(saved.status == .done && saved.summary?.overview == "Summary")
            }
        }
        #expect(provider.log.calls == 3)
    }
}
