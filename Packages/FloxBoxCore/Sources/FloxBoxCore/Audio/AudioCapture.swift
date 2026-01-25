import AVFoundation
import AudioToolbox
import CoreAudio

public final class AudioCapture {
    public typealias Handler = (Data) -> Void

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var preferredInputDeviceID: AudioDeviceID?
    private var isRunning = false

    public init() {}

    public func setPreferredInputDevice(_ deviceID: AudioDeviceID?) {
        preferredInputDeviceID = deviceID
    }

    public static func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    public func start(handler: @escaping Handler) throws {
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        if let deviceID = preferredInputDeviceID {
            try setInputDevice(deviceID, on: inputNode)
        }
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24_000,
            channels: 1,
            interleaved: true
        )!

        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.converter else { return }

            let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: AVAudioFrameCount(1024)
            )
            guard let convertedBuffer else { return }

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
            guard error == nil else { return }

            handler(convertedBuffer.pcm16Data())
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }
}

private enum AudioCaptureError: Error {
    case missingAudioUnit
    case audioUnit(OSStatus)
}

private func setInputDevice(_ deviceID: AudioDeviceID, on inputNode: AVAudioInputNode) throws {
    guard let audioUnit = inputNode.audioUnit else {
        throw AudioCaptureError.missingAudioUnit
    }
    var deviceID = deviceID
    let status = AudioUnitSetProperty(
        audioUnit,
        kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global,
        0,
        &deviceID,
        UInt32(MemoryLayout<AudioDeviceID>.size)
    )
    guard status == noErr else {
        throw AudioCaptureError.audioUnit(status)
    }
}

private extension AVAudioPCMBuffer {
    func pcm16Data() -> Data {
        guard let channel = int16ChannelData else { return Data() }
        let frames = Int(frameLength)
        return Data(bytes: channel[0], count: frames * MemoryLayout<Int16>.size)
    }
}
