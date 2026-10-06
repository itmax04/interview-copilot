@preconcurrency import AVFoundation

/// Чтение аудиофайла в 16 кГц моно Float32 (фикстуры evals/audio, тесты и замеры).
public enum AudioFileReader {
    public static func read16kMono(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)) else { return [] }
        try file.read(into: buffer)
        return PCMConverter().convert(buffer)
    }
}

/// Память процесса (phys_footprint, как `footprint`/«Мониторинг системы») — для замеров AC-05.
public enum ProcessMemory {
    public static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}
