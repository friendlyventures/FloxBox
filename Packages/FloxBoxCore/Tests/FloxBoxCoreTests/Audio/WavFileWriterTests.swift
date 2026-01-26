@testable import FloxBoxCore
import XCTest

final class WavFileWriterTests: XCTestCase {
    func testWavWriterCreatesValidHeaderAndSize() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ptt.wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try WavFileWriter(url: url, sampleRate: 24000, channels: 1)
        writer.append(Data([0x01, 0x02, 0x03, 0x04]))
        try writer.finalize()

        let data = try Data(contentsOf: url)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(data.count, 44 + 4)
    }
}
