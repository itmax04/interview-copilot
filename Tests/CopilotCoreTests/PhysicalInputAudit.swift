import CopilotCore
import CoreAudio
import Foundation
import Synchronization
import Testing

@Suite @MainActor struct PhysicalInputAudit {
    private struct SampleCounts {
        var total = 0
        var nonzero = 0
        var nonfinite = 0

        mutating func append(_ samples: [Float]) {
            total += samples.count
            for sample in samples {
                if !sample.isFinite {
                    nonfinite += 1
                } else if sample != 0 {
                    nonzero += 1
                }
            }
        }
    }

    // Requires an authorized test host and two physical inputs. Temporarily changes the system default.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["IC_TEST_PHYSICAL_INPUTS"] == "1"))
    func switchDuringCapture() async throws {
        try #require(Permissions.microphone == .granted)
        let original = try defaultInput()
        let inputs = try inputDevices()
        try #require(inputs.contains(original))
        let alternate = try #require(inputs.first { $0 != original })

        let counts = Mutex(SampleCounts())
        let capture = MicrophoneCapture { samples in
            counts.withLock { $0.append(samples) }
        }
        defer {
            capture.stop()
            // A fatal AVFoundation exception bypasses defer. The caller must restore the default in that case.
            do { try setDefaultInput(original) } catch { Issue.record(error) }
        }

        try capture.start()
        for (label, device) in [("original", original), ("alternate", alternate), ("restored", original)] {
            if try defaultInput() != device { try setDefaultInput(device) }
            try await expectStableCapture(label, on: device, counts: counts)
            #expect(capture.isRunning)
        }
    }

    private func expectStableCapture(_ label: String, on device: AudioDeviceID, counts: borrowing Mutex<SampleCounts>) async throws {
        // Continuity can report the new device before it begins delivering samples.
        let deadline = ContinuousClock.now + .seconds(15)
        let expectedSampleCount = 12_000...22_000
        var samples = 0
        var nonzero = 0
        var usingSelectedInput = false
        repeat {
            let startedOnSelectedInput = try activeInputDevices() == [device]
            let before = counts.withLock { $0 }
            try await Task.sleep(for: .seconds(1))
            let after = counts.withLock { $0 }
            try #require(after.nonfinite == 0)
            samples = after.total - before.total
            nonzero = after.nonzero - before.nonzero
            let active = try activeInputDevices()
            let isDefault = try defaultInput() == device
            usingSelectedInput = startedOnSelectedInput && active == [device] && isDefault
            if usingSelectedInput, expectedSampleCount.contains(samples), nonzero >= 100 { break }
        } while ContinuousClock.now < deadline
        print("Physical input \(label): \(samples) samples, \(nonzero) nonzero, selected device active: \(usingSelectedInput)")
        #expect(expectedSampleCount.contains(samples))
        #expect(nonzero >= 100)
        #expect(usingSelectedInput)
    }

    private func defaultInput() throws -> AudioDeviceID {
        var property = globalProperty(kAudioHardwarePropertyDefaultInputDevice)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(system, &property, 0, nil, &size, &device)
        try #require(status == noErr)
        return device
    }

    private func setDefaultInput(_ device: AudioDeviceID) throws {
        var property = globalProperty(kAudioHardwarePropertyDefaultInputDevice)
        var device = device
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(system, &property, 0, nil, size, &device)
        try #require(status == noErr)
    }

    private func inputDevices() throws -> [AudioDeviceID] {
        var property = globalProperty(kAudioHardwarePropertyDevices)
        return try deviceIDs(from: system, property: &property).filter { device in
            var transportProperty = globalProperty(kAudioDevicePropertyTransportType)
            var transport: UInt32 = kAudioDeviceTransportTypeUnknown
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(device, &transportProperty, 0, nil, &transportSize, &transport) == noErr,
                  transport != kAudioDeviceTransportTypeAggregate, transport != kAudioDeviceTransportTypeVirtual else {
                return false
            }
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                     mScope: kAudioObjectPropertyScopeInput,
                                                     mElement: kAudioObjectPropertyElementMain)
            var streamBytes: UInt32 = 0
            return AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamBytes) == noErr && streamBytes > 0
        }
    }

    private func activeInputDevices() throws -> [AudioDeviceID] {
        var property = globalProperty(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = ProcessInfo.processInfo.processIdentifier
        var process = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(system, &property, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &process)
        try #require(status == noErr)
        guard process != kAudioObjectUnknown else { return [] }
        var inputs = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyDevices,
                                                mScope: kAudioObjectPropertyScopeInput,
                                                mElement: kAudioObjectPropertyElementMain)
        return try deviceIDs(from: process, property: &inputs)
    }

    private func deviceIDs(from object: AudioObjectID, property: inout AudioObjectPropertyAddress) throws -> [AudioDeviceID] {
        var size: UInt32 = 0
        try #require(AudioObjectGetPropertyDataSize(object, &property, 0, nil, &size) == noErr)
        guard size > 0 else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        try #require(AudioObjectGetPropertyData(object, &property, 0, nil, &size, &devices) == noErr)
        return devices
    }

    private var system: AudioObjectID { AudioObjectID(kAudioObjectSystemObject) }

    private func globalProperty(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}
