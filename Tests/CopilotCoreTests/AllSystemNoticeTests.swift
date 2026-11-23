import Testing
@testable import CopilotCore

@Suite("COPILOT-16 R-06 — предупреждение о «Всём системном звуке»")
struct AllSystemNoticeTests {
    let telegram = RunningAppInfo(bundleID: "ru.keepcoder.Telegram", name: "Telegram")
    let chrome = RunningAppInfo(bundleID: "com.google.Chrome", name: "Google Chrome")
    let notes = RunningAppInfo(bundleID: "com.apple.Notes", name: "Notes")

    @Test func shownOnlyForAllSystem() {
        #expect(AudioSourceResolver.allSystemNotice(for: .allSystem, running: []) != nil)
        #expect(AudioSourceResolver.allSystemNotice(for: .app(telegram), running: [telegram]) == nil)
        #expect(AudioSourceResolver.allSystemNotice(for: .microphone, running: []) == nil)
        #expect(AudioSourceResolver.allSystemNotice(for: .none, running: []) == nil)
    }

    @Test func callOnlyOfferedWhenCallAppRunning() {
        #expect(AudioSourceResolver.allSystemNotice(for: .allSystem, running: [notes])?.callApp == nil)
        #expect(AudioSourceResolver.allSystemNotice(for: .allSystem, running: [notes, telegram])?.callApp
                == RunningAppInfo(bundleID: "ru.keepcoder.Telegram", name: "Telegram"))
    }

    @Test func callAppFollowsAutoPriority() {
        // Chrome стоит раньше Telegram в порядке Auto.
        #expect(AudioSourceResolver.runningCallApp([telegram, chrome])?.name == "Chrome")
    }

    @Test func autoFallbackWithoutCallAppIsAllSystemWithNotice() {
        let resolved = AudioSourceResolver.resolve(.auto, running: [notes])
        #expect(AudioSourceResolver.allSystemNotice(for: resolved, running: [notes]) != nil)
    }
}
