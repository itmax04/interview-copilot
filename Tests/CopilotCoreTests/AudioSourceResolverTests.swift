import Testing
@testable import CopilotCore

@Suite("AudioSourceResolver — R-01")
struct AudioSourceResolverTests {
    let zoom = RunningAppInfo(bundleID: "us.zoom.xos", name: "zoom.us")
    let teams = RunningAppInfo(bundleID: "com.microsoft.teams2", name: "Microsoft Teams")
    let chrome = RunningAppInfo(bundleID: "com.google.Chrome", name: "Google Chrome")
    let telegram = RunningAppInfo(bundleID: "ru.keepcoder.Telegram", name: "Telegram")
    let telegramDesktop = RunningAppInfo(bundleID: "org.telegram.desktop", name: "Telegram Desktop")
    let discord = RunningAppInfo(bundleID: "com.hnc.Discord", name: "Discord")
    let safari = RunningAppInfo(bundleID: "com.apple.Safari", name: "Safari")

    @Test func autoPrefersZoomThenTeamsThenChromeThenTelegramThenDiscordThenSafari() {
        #expect(AudioSourceResolver.resolve(.auto, running: [telegram, chrome, teams, zoom]) == .app(RunningAppInfo(bundleID: "us.zoom.xos", name: "Zoom")))
        #expect(AudioSourceResolver.resolve(.auto, running: [telegram, chrome, teams]) == .app(RunningAppInfo(bundleID: "com.microsoft.teams2", name: "Teams")))
        #expect(AudioSourceResolver.resolve(.auto, running: [telegram, chrome]) == .app(RunningAppInfo(bundleID: "com.google.Chrome", name: "Chrome")))
        #expect(AudioSourceResolver.resolve(.auto, running: [safari, discord, telegram]) == .app(RunningAppInfo(bundleID: "ru.keepcoder.Telegram", name: "Telegram")))
        #expect(AudioSourceResolver.resolve(.auto, running: [telegramDesktop]) == .app(RunningAppInfo(bundleID: "org.telegram.desktop", name: "Telegram")))
        #expect(AudioSourceResolver.resolve(.auto, running: [safari, discord]) == .app(RunningAppInfo(bundleID: "com.hnc.Discord", name: "Discord")))
    }

    @Test func autoFallsBackToAllSystemWhenNoCallAppRunning() {
        let notes = RunningAppInfo(bundleID: "com.apple.Notes", name: "Notes")
        #expect(AudioSourceResolver.resolve(.auto, running: [safari]) == .app(RunningAppInfo(bundleID: "com.apple.Safari", name: "Safari")))
        #expect(AudioSourceResolver.resolve(.auto, running: [notes]) == .allSystem)
        #expect(AudioSourceResolver.resolve(.auto, running: []) == .allSystem)
    }

    @Test func specificApp() {
        let setting = AudioSourceSetting.app(bundleID: "com.apple.Safari", name: "Safari")
        #expect(AudioSourceResolver.resolve(setting, running: [chrome, safari]) == .app(safari))
        #expect(AudioSourceResolver.resolve(setting, running: [chrome]) == .none)
    }

    @Test func microphoneNeedsNoRunningApp() {
        #expect(AudioSourceResolver.resolve(.microphone, running: []) == .microphone)
        #expect(ResolvedAudioSource.microphone.displayName == "Microphone")
    }

    @Test func allSystem() {
        #expect(AudioSourceResolver.resolve(.allSystem, running: []) == .allSystem)
    }

    @Test func helpersBelongToApp() {
        #expect(AudioSourceResolver.belongsTo("com.google.Chrome", app: "com.google.Chrome"))
        #expect(AudioSourceResolver.belongsTo("com.google.Chrome.helper", app: "com.google.Chrome"))
        #expect(AudioSourceResolver.belongsTo("com.google.Chrome.helper.Renderer", app: "com.google.Chrome"))
        #expect(!AudioSourceResolver.belongsTo("com.google.Chromecast", app: "com.google.Chrome"))
        #expect(!AudioSourceResolver.belongsTo("us.zoom.xos", app: "com.google.Chrome"))
    }
}
