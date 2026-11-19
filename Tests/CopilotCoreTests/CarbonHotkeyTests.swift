import AppKit
import Carbon.HIToolbox
import CopilotCore
import Testing

@Suite struct CarbonHotkeyTests {
    // Carbon keeps the handler's context for the lifetime of the test host.
    @MainActor private static let center = HotkeyCenter { _ in }

    // Opt in on a logged-in Mac: this test briefly reserves real global shortcuts.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["IC_TEST_CARBON_HOTKEYS"] == "1"))
    @MainActor func conflictsAcrossProcessesAndActions() async throws {
        _ = NSApplication.shared
        let control = Pipe()
        let ready = Pipe()
        let holder = Process()
        holder.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        holder.arguments = [try #require(Bundle.module.url(forResource: "hold-carbon-hotkey", withExtension: "swift",
                                                           subdirectory: "Fixtures")).path]
        holder.standardInput = control
        holder.standardOutput = ready
        try holder.run()
        defer {
            if holder.isRunning {
                control.fileHandleForWriting.closeFile()
                holder.waitUntilExit()
            }
        }
        let signal = await Task.detached { ready.fileHandleForReading.readData(ofLength: 1) }.value
        try #require(signal == Data([1]))

        let center = Self.center
        defer {
            center.unregisterSession()
            center.unregisterAll()
        }
        let mods = UInt32(controlKey | optionKey | shiftKey)
        let held = HotkeyBinding(keyCode: UInt32(kVK_ANSI_L), modifiers: mods)
        let local = HotkeyBinding(keyCode: UInt32(kVK_F18), modifiers: mods)
        // Leave the user's regular global shortcuts alone.
        var bindings = Dictionary(uniqueKeysWithValues: HotkeyAction.allCases.map {
            ($0, HotkeyBinding(keyCode: 0, modifiers: 0))
        })
        bindings[.newSession] = held
        bindings[.answerNow] = local
        bindings[.togglePause] = local
        let failures = center.register(bindings)
        #expect(failures[.answerNow] == nil)
        #expect(failures[.togglePause] == L10n.f("сочетание уже назначено действию «%@»", HotkeyAction.answerNow.title))
        #expect(failures[.newSession] == L10n.t("сочетание занято другим приложением"))

        // Isolate the session path from global registrations in this process.
        center.unregisterAll()
        #expect(center.registerSession([.chat: held]) == [.chat])
        center.unregisterSession()
        control.fileHandleForWriting.closeFile()
        await Task.detached { holder.waitUntilExit() }.value
        try #require(holder.terminationStatus == 0)
        #expect(center.registerSession([.chat: held]).isEmpty)
        // A global edit takes priority over a session alias and refreshes its fallback.
        #expect(center.register(bindings)[.newSession] == nil)
        #expect(center.sessionFailures == [.chat])
        bindings[.newSession] = HotkeyBinding(keyCode: 0, modifiers: 0)
        center.register(bindings)
        #expect(center.sessionFailures.isEmpty)
        #expect(center.sessionActive)
        center.unregisterSession()
        #expect(!center.sessionActive)
        bindings[.newSession] = held
        #expect(center.register(bindings)[.newSession] == nil)
    }
}
