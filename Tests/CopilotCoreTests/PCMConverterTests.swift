@preconcurrency import AVFoundation
import Testing
@testable import CopilotCore

@Suite("PCMConverter — continuous capture")
struct PCMConverterTests {
    @Test func stereo48kCapturePreservesDurationAndSpeechLevelAcrossBlocks() {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                   channels: 2, interleaved: false)!
        let converter = PCMConverter()
        var output: [Float] = []
        // 3 с непрерывного сигнала, блоки по 10 мс, как при захвате звонка.
        for block in 0..<300 {
            let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480)!
            pcm.frameLength = 480
            for i in 0..<480 {
                let value = Float(0.3 * sin(2 * Double.pi * 440 * Double(block * 480 + i) / 48_000))
                pcm.floatChannelData![0][i] = value
                pcm.floatChannelData![1][i] = value
            }
            output += converter.convert(pcm)
        }
        // Допускается только начальная задержка фильтра, а не потери на каждом блоке.
        #expect(abs(output.count - 48_000) <= 32)
        #expect(converter.lastError.isEmpty)
        #expect(output.allSatisfy { $0.isFinite && abs($0) < 0.32 })
        let rms = EnergyVAD.rmsDB(output.dropFirst(1000))
        #expect(abs(rms - (-13.47)) < 0.3)
        let crossings = zip(output, output.dropFirst()).filter { $0.0 < 0 && $0.1 >= 0 }.count
        let hz = Double(crossings) / (Double(output.count) / 16_000)
        #expect(abs(hz - 440) < 2)
    }
}
