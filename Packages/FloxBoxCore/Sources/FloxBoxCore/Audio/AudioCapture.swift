import AudioToolbox
import AVFoundation
import CoreAudio

public final class AudioCapture {
    public typealias Handler = (Data) -> Void

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var preferredInputDeviceID: AudioDeviceID?
    private var pendingData = Data()
    private var pendingHandler: Handler?
    private var isRunning = false
    private let chunkSamples: Int = 3072

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
        pendingHandler = handler
        pendingData.removeAll(keepingCapacity: true)

        let inputNode = engine.inputNode
        if let deviceID = preferredInputDeviceID {
            try setInputDevice(deviceID, on: inputNode)
        }
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24000,
            channels: 1,
            interleaved: false,
        )!

        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let converter else { return }

            let ratio = targetFormat.sampleRate / inputFormat.sampleRate
            let estimatedFrames = Int(ceil(Double(buffer.frameLength) * ratio))
            let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: AVAudioFrameCount(max(1, estimatedFrames)),
            )
            guard let convertedBuffer else { return }

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
            guard error == nil else { return }
            guard convertedBuffer.frameLength > 0 else { return }

            appendPCMData(convertedBuffer.pcm16Data())
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        flushPending()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        pendingHandler = nil
    }

    private func appendPCMData(_ data: Data) {
        guard !data.isEmpty, let handler = pendingHandler else { return }
        pendingData.append(data)
        let chunkBytes = chunkSamples * MemoryLayout<Int16>.size
        while pendingData.count >= chunkBytes {
            let chunk = pendingData.prefix(chunkBytes)
            pendingData.removeSubrange(0 ..< chunkBytes)
            handler(Data(chunk))
        }
    }

    private func flushPending() {
        guard let handler = pendingHandler, !pendingData.isEmpty else { return }
        handler(pendingData)
        pendingData.removeAll(keepingCapacity: true)
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
        UInt32(MemoryLayout<AudioDeviceID>.size),
    )
    guard status == noErr else {
        throw AudioCaptureError.audioUnit(status)
    }
}

private extension AVAudioPCMBuffer {
    func pcm16Data() -> Data {
        let bufferList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
        guard let first = bufferList.first, let data = first.mData else { return Data() }
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        let expectedSize = Int(frameLength) * bytesPerFrame
        let byteCount = min(Int(first.mDataByteSize), expectedSize)
        return Data(bytes: data, count: byteCount)
    }
}
