import CoreAudio
import Foundation

struct AudioDeviceOption: Identifiable, Equatable {
    let id: String
    let coreAudioID: AudioDeviceID
    let name: String
    let isDefault: Bool
}

enum AudioDeviceCatalog {
    static func inputs() -> [AudioDeviceOption] { devices(scope: kAudioDevicePropertyScopeInput) }
    static func outputs() -> [AudioDeviceOption] { devices(scope: kAudioDevicePropertyScopeOutput) }
    static func defaultOutputUID() -> String? {
        let id = defaultDeviceID(scope: kAudioDevicePropertyScopeOutput)
        return stringProperty(id, selector: kAudioDevicePropertyDeviceUID)
    }

    @discardableResult
    static func setDefaultOutput(uid: String) -> Bool {
        guard let device = outputs().first(where: { $0.id == uid }) else { return false }
        var id = device.coreAudioID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let outputStatus = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &id
        )
        address.mSelector = kAudioHardwarePropertyDefaultSystemOutputDevice
        _ = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &id
        )
        return outputStatus == noErr
    }

    private static func devices(scope: AudioObjectPropertyScope) -> [AudioDeviceOption] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &byteCount) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(byteCount) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &byteCount, &ids) == noErr else { return [] }

        let defaultDevice = defaultDeviceID(scope: scope)
        return ids.compactMap { id in
            guard channelCount(deviceID: id, scope: scope) > 0,
                  let name = stringProperty(id, selector: kAudioObjectPropertyName),
                  let uid = stringProperty(id, selector: kAudioDevicePropertyDeviceUID)
            else { return nil }
            return AudioDeviceOption(id: uid, coreAudioID: id, name: name, isDefault: id == defaultDevice)
        }
        .sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func defaultDeviceID(scope: AudioObjectPropertyScope) -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: scope == kAudioDevicePropertyScopeInput
                ? kAudioHardwarePropertyDefaultInputDevice
                : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    private static func stringProperty(_ id: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, UnsafeMutableRawPointer(pointer))
        }
        guard status == noErr, let name else { return nil }
        return name.takeUnretainedValue() as String
    }

    private static func channelCount(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
