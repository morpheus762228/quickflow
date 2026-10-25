import Foundation
import CoreAudio

struct AudioInputDevice: Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isVirtual: Bool
    let isDefault: Bool
    let channels: Int

    var displayName: String {
        isVirtual ? "\(name) (virtual)" : name
    }
}

enum AudioDevices {
    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func allInputs() -> [AudioInputDevice] {
        let defaultID = defaultInputID()
        var propertyAddress = address(kAudioHardwarePropertyDevices)
        var dataSize: UInt32 = 0
        let systemObject = AudioObjectID(kAudioObjectSystemObject)

        guard AudioObjectGetPropertyDataSize(systemObject, &propertyAddress, 0, nil, &dataSize) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }

        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(systemObject, &propertyAddress, 0, nil, &dataSize, &ids) == noErr else {
            return []
        }

        var devices: [AudioInputDevice] = []
        for id in ids {
            let channels = inputChannelCount(id)
            guard channels > 0 else { continue }
            guard let name = stringProperty(id, kAudioObjectPropertyName), !name.isEmpty else { continue }
            let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) ?? "\(id)"
            let transport = transportType(id)
            let virtual = transport == kAudioDeviceTransportTypeVirtual
                || transport == kAudioDeviceTransportTypeAggregate
                || name.localizedCaseInsensitiveContains("blackhole")
                || name.localizedCaseInsensitiveContains("soundflower")

            devices.append(AudioInputDevice(
                id: id,
                uid: uid,
                name: name,
                isVirtual: virtual,
                isDefault: id == defaultID,
                channels: channels
            ))
        }

        return devices.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            if lhs.isVirtual != rhs.isVirtual { return !lhs.isVirtual }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func defaultInput() -> AudioInputDevice? {
        guard let id = defaultInputID() else { return nil }
        return device(id: id)
    }

    private static func defaultInputID() -> AudioDeviceID? {
        var propertyAddress = address(kAudioHardwarePropertyDefaultInputDevice)
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    static func device(id: AudioDeviceID) -> AudioInputDevice? {
        guard inputChannelCount(id) > 0,
              let name = stringProperty(id, kAudioObjectPropertyName) else { return nil }
        let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) ?? "\(id)"
        let transport = transportType(id)
        return AudioInputDevice(
            id: id,
            uid: uid,
            name: name,
            isVirtual: transport == kAudioDeviceTransportTypeVirtual
                || transport == kAudioDeviceTransportTypeAggregate
                || name.localizedCaseInsensitiveContains("blackhole"),
            isDefault: defaultInputID() == id,
            channels: inputChannelCount(id)
        )
    }

    static func device(uid: String) -> AudioInputDevice? {
        guard !uid.isEmpty else { return preferredInput() }
        return allInputs().first { $0.uid == uid } ?? preferredInput()
    }

    /// The device QuickFlow should record from when the user has not chosen one:
    /// the system default unless it is virtual (BlackHole, Loopback, an aggregate),
    /// in which case the first real microphone wins.
    static func preferredInput() -> AudioInputDevice? {
        let inputs = allInputs()
        if let match = inputs.first(where: { $0.uid == Preferences.shared.inputDeviceUID }) {
            return match
        }
        if let systemDefault = inputs.first(where: { $0.isDefault }), !systemDefault.isVirtual {
            return systemDefault
        }
        return inputs.first(where: { !$0.isVirtual }) ?? inputs.first
    }

    private static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var propertyAddress = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &propertyAddress, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        guard AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &size, list) == noErr else {
            return 0
        }
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var propertyAddress = address(selector)
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }

    private static func transportType(_ id: AudioDeviceID) -> UInt32 {
        var propertyAddress = address(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &size, &value) == noErr else {
            return 0
        }
        return value
    }
}
