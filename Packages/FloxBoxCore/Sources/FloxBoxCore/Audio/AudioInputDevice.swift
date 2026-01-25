import CoreAudio
import Foundation

public struct AudioInputDevice: Identifiable, Equatable {
    public let id: AudioDeviceID
    public let name: String
    public let uid: String

    public init(id: AudioDeviceID, name: String, uid: String) {
        self.id = id
        self.name = name
        self.uid = uid
    }
}

public enum AudioInputDeviceProvider {
    public static func availableDevices() -> [AudioInputDevice] {
        let deviceIDs = allDeviceIDs()
        let inputDevices = deviceIDs.compactMap { deviceID -> AudioInputDevice? in
            guard deviceHasInput(deviceID) else { return nil }
            let name = deviceName(deviceID) ?? "Unknown"
            let uid = deviceUID(deviceID) ?? "\(deviceID)"
            return AudioInputDevice(id: deviceID, name: name, uid: uid)
        }
        return inputDevices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func defaultInputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        guard status == noErr else { return nil }
        return deviceID
    }
}

private func allDeviceIDs() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    let status = AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &dataSize
    )
    guard status == noErr else { return [] }
    let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    var deviceIDs = Array(repeating: AudioDeviceID(0), count: deviceCount)
    let readStatus = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &dataSize,
        &deviceIDs
    )
    guard readStatus == noErr else { return [] }
    return deviceIDs
}

private func deviceHasInput(_ deviceID: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    let status = AudioObjectGetPropertyDataSize(
        deviceID,
        &address,
        0,
        nil,
        &dataSize
    )
    guard status == noErr else { return false }
    let bufferListPointer = UnsafeMutableRawPointer.allocate(
        byteCount: Int(dataSize),
        alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { bufferListPointer.deallocate() }
    let readStatus = AudioObjectGetPropertyData(
        deviceID,
        &address,
        0,
        nil,
        &dataSize,
        bufferListPointer
    )
    guard readStatus == noErr else { return false }
    let audioBufferList = bufferListPointer.assumingMemoryBound(to: AudioBufferList.self)
    let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
    let channels = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    return channels > 0
}

private func deviceName(_ deviceID: AudioDeviceID) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var name: Unmanaged<CFString>?
    var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = AudioObjectGetPropertyData(
        deviceID,
        &address,
        0,
        nil,
        &dataSize,
        &name
    )
    guard status == noErr, let name else { return nil }
    return name.takeUnretainedValue() as String
}

private func deviceUID(_ deviceID: AudioDeviceID) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var uid: Unmanaged<CFString>?
    var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = AudioObjectGetPropertyData(
        deviceID,
        &address,
        0,
        nil,
        &dataSize,
        &uid
    )
    guard status == noErr, let uid else { return nil }
    return uid.takeUnretainedValue() as String
}
