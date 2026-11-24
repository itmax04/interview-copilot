import Testing
@testable import CopilotCore

@Suite struct MicSilenceDetectorTests {
    /// Прогоняет `seconds` секунд замеров по 10 Гц, возвращает сколько раз сработало начало эпизода.
    private func run(_ d: inout MicSilenceDetector, from: Double, seconds: Double, level: Float = -120,
                     muted: Bool = false, active: Bool = true) -> Int {
        var starts = 0
        var t = from
        while t < from + seconds {
            if d.update(levelDB: level, muted: muted, active: active, now: t) { starts += 1 }
            t += 0.1
        }
        return starts
    }

    @Test func noticeAfterTenSecondsOfDigitalZero() {
        var d = MicSilenceDetector()
        let early = run(&d, from: 0, seconds: 9.5)
        #expect(early == 0)
        #expect(!d.isSilent)
        let late = run(&d, from: 9.5, seconds: 2)
        #expect(late == 1)
        #expect(d.isSilent)
    }

    @Test func oneStartPerEpisodeAndClearsWhenLevelRises() {
        var d = MicSilenceDetector()
        #expect(run(&d, from: 0, seconds: 30) == 1)
        #expect(d.isSilent)
        _ = d.update(levelDB: -60, muted: false, active: true, now: 30)
        #expect(!d.isSilent)
        // Новый эпизод — новая запись.
        #expect(run(&d, from: 31, seconds: 12) == 1)
    }

    @Test func mutedMicKeepsMuteBannerPriority() {
        var d = MicSilenceDetector()
        #expect(run(&d, from: 0, seconds: 30, muted: true) == 0)
        #expect(!d.isSilent)
        // Снятие mute начинает отсчёт заново.
        #expect(run(&d, from: 30, seconds: 5) == 0)
        #expect(!d.isSilent)
    }

    @Test func inactiveChannelNeverRaisesNotice() {
        var d = MicSilenceDetector()
        #expect(run(&d, from: 0, seconds: 30, active: false) == 0)
        #expect(!d.isSilent)
    }

    @Test func quietButNotZeroIsNotSilent() {
        var d = MicSilenceDetector()
        #expect(run(&d, from: 0, seconds: 30, level: -90) == 0)
        #expect(!d.isSilent)
    }

    @Test func shortSoundResetsTheCountdown() {
        var d = MicSilenceDetector()
        _ = run(&d, from: 0, seconds: 8)
        _ = d.update(levelDB: -50, muted: false, active: true, now: 8)
        #expect(run(&d, from: 8.1, seconds: 8) == 0)
        #expect(!d.isSilent)
    }
}
