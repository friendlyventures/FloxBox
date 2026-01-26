@testable import FloxBoxCore
import XCTest

final class RealtimeWebSocketClientTests: XCTestCase {
    func testClientInitializes() {
        let client = RealtimeWebSocketClient(apiKey: "test-key")
        _ = client.events
    }

    func testBaseURLUsesWss() {
        XCTAssertEqual(RealtimeAPI.baseURL.scheme, "wss")
    }

    func testClearAudioBufferEncodesEvent() throws {
        let payload = try JSONEncoder().encode(InputAudioBufferClearEvent())
        let text = String(data: payload, encoding: .utf8)!
        XCTAssertTrue(text.contains("\"type\":\"input_audio_buffer.clear\""))
    }
}
