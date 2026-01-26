import Foundation

public final class WavFileWriter {
    private let handle: FileHandle
    private let sampleRate: UInt32
    private let channels: UInt16
    private var dataSize: UInt32 = 0
    private var isFinalized = false

    public init(url: URL, sampleRate: UInt32, channels: UInt16) throws {
        self.sampleRate = sampleRate
        self.channels = channels
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        writeHeaderPlaceholder()
    }

    deinit {
        try? handle.close()
    }

    public func append(_ data: Data) {
        guard !isFinalized, !data.isEmpty else { return }
        handle.write(data)
        dataSize &+= UInt32(data.count)
    }

    public func finalize() throws {
        guard !isFinalized else { return }
        isFinalized = true
        try updateHeaderSizes()
        try handle.close()
    }

    private func writeHeaderPlaceholder() {
        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        header.append(UInt32(0).littleEndianData)
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(UInt32(16).littleEndianData)
        header.append(UInt16(1).littleEndianData) // PCM
        header.append(channels.littleEndianData)
        header.append(sampleRate.littleEndianData)
        let byteRate = sampleRate * UInt32(channels) * 2
        header.append(byteRate.littleEndianData)
        let blockAlign = UInt16(channels * 2)
        header.append(blockAlign.littleEndianData)
        header.append(UInt16(16).littleEndianData) // bits per sample
        header.append(contentsOf: "data".utf8)
        header.append(UInt32(0).littleEndianData)
        handle.write(header)
    }

    private func updateHeaderSizes() throws {
        let riffSize = UInt32(36) &+ dataSize
        try handle.seek(toOffset: 4)
        handle.write(riffSize.littleEndianData)
        try handle.seek(toOffset: 40)
        handle.write(dataSize.littleEndianData)
        try handle.seekToEnd()
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var value = littleEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}
