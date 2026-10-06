@preconcurrency import AVFoundation
import CoreMedia

/// Приводит звук к 16 кГц, моно, Float32 — формат для whisper (R-03) и VAD.
public final class PCMConverter: @unchecked Sendable {
    public static let targetSampleRate: Double = 16_000
    public static let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate,
                                                   channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    /// Последняя ошибка преобразования — для диагностики в логах (без звука).
    public private(set) var lastError = ""

    public init() {}

    public func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let format = buffer.format
        if format.sampleRate == Self.targetSampleRate, format.channelCount == 1,
           format.commonFormat == .pcmFormatFloat32, let data = buffer.floatChannelData {
            return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
        }
        if sourceFormat != format {
            converter = AVAudioConverter(from: format, to: Self.targetFormat)
            sourceFormat = format
        }
        guard let converter else {
            lastError = "no converter from \(format)"
            return []
        }
        let ratio = Self.targetSampleRate / format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: capacity) else { return [] }
        // Блок вызывается синхронно внутри convert; флаг в классе-обёртке, чтобы не ловить предупреждения Sendable.
        final class Once: @unchecked Sendable { var consumed = false }
        let once = Once()
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if once.consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            once.consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let data = out.floatChannelData else {
            lastError = "AVAudioConverter \(error?.localizedDescription ?? "nil") from \(format)"
            return []
        }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
    }

    /// Аудио-сэмплы ScreenCaptureKit (`CMSampleBuffer`) → 16 кГц моно.
    public func convert(_ sampleBuffer: CMSampleBuffer) -> [Float] {
        guard let description = sampleBuffer.formatDescription else { return [] }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frames = AVAudioFrameCount(sampleBuffer.numSamples)
        guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return [] }
        pcm.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames),
                                                                  into: pcm.mutableAudioBufferList)
        guard status == noErr else {
            lastError = "CopyPCMData status \(status)"
            return []
        }
        return convert(pcm)
    }
}
