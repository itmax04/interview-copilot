import AppKit
import Carbon.HIToolbox

NSApplication.shared.setActivationPolicy(.prohibited)
var ref: EventHotKeyRef?
let status = RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(controlKey | optionKey | shiftKey),
                                 EventHotKeyID(signature: 0x54455354, id: 1), GetApplicationEventTarget(),
                                 UInt32(kEventHotKeyExclusive), &ref)
guard status == noErr, let ref else {
    FileHandle.standardError.write(Data("Fixture registration failed (OSStatus \(status))\n".utf8))
    exit(1)
}
FileHandle.standardOutput.write(Data([1]))
_ = FileHandle.standardInput.readDataToEndOfFile()
exit(UnregisterEventHotKey(ref) == noErr ? 0 : 1)
