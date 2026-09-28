import AudioToolbox
import CoreAudio

/// Volume and mute on the default output device.
enum CoreAudioVolume {
    static func volume() throws -> Int {
        let device = try defaultOutputDevice()
        var address = volumeAddress
        guard AudioObjectHasProperty(device, &address) else { throw SystemControlError.noVolumeControl }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        guard status == noErr else { throw SystemControlError.failed("couldn't read the volume (\(status))") }
        return Int((value * 100).rounded())
    }

    static func setVolume(_ percent: Int) throws {
        let device = try defaultOutputDevice()
        var address = volumeAddress
        try requireSettable(device, &address)
        var value = Float32(min(100, max(0, percent))) / 100
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        guard status == noErr else { throw SystemControlError.failed("couldn't set the volume (\(status))") }
    }

    static func setMuted(_ muted: Bool) throws {
        let device = try defaultOutputDevice()
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        try requireSettable(device, &address)
        var value: UInt32 = muted ? 1 : 0
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        guard status == noErr else { throw SystemControlError.failed("couldn't change mute (\(status))") }
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultOutputDevice() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != 0 else { throw SystemControlError.failed("no audio output device") }
        return device
    }

    private static func requireSettable(_ device: AudioDeviceID, _ address: inout AudioObjectPropertyAddress) throws {
        guard AudioObjectHasProperty(device, &address) else { throw SystemControlError.noVolumeControl }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else {
            throw SystemControlError.noVolumeControl
        }
    }
}
