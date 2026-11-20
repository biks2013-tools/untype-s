#if os(macOS)
import AudioToolbox
import CoreAudio
import Foundation

/// The volume of the Mac's sound output (the device the system plays on),
/// 0…1. Nil / false when that device has no volume untype can read or set
/// (some displays and audio interfaces).
public enum SystemOutputVolume {
    private static func defaultOutputDevice() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    /// The device's one volume, as the volume keys and the menu bar set it.
    private static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    public static func get() -> Float? {
        guard let device = defaultOutputDevice() else {
            return nil
        }
        var address = volumeAddress()
        guard AudioObjectHasProperty(device, &address) else {
            return nil
        }
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr ? volume : nil
    }

    @discardableResult
    public static func set(_ volume: Float) -> Bool {
        guard let device = defaultOutputDevice() else {
            return false
        }
        var address = volumeAddress()
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else {
            return false
        }
        var value = Float32(min(1, max(0, volume)))
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }
}

/// Lowers the Mac's sound while the user dictates to the meeting assistant
/// (plan-078): the call playing from the loudspeakers is then not louder
/// than the user at the microphone. Loud sound is lowered to `quiet`; sound
/// already at or below it is left alone. When the dictation ends the volume
/// goes back, unless the user changed it meanwhile.
public struct OutputVolumeDuck: Equatable, Sendable {
    /// The volume during the dictation, of 1.
    public static let quiet: Float = 0.15

    /// The volume before the dictation (nil: nothing was lowered).
    public private(set) var previous: Float?

    public init() {}

    /// What to set the volume to at the start of a dictation, given the
    /// volume now (nil: leave it).
    public mutating func begin(current: Float?) -> Float? {
        guard previous == nil, let current, current > Self.quiet + 0.01 else {
            return nil
        }
        previous = current
        return Self.quiet
    }

    /// What to set the volume to at the end, given the volume now (nil:
    /// leave it, nothing was lowered or the user changed it meanwhile).
    public mutating func end(current: Float?) -> Float? {
        guard let previous else {
            return nil
        }
        self.previous = nil
        guard let current, abs(current - Self.quiet) < 0.02 else {
            return nil
        }
        return previous
    }
}
#endif
