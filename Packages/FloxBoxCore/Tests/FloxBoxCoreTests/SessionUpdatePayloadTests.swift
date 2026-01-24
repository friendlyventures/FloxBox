import XCTest
@testable import FloxBoxCore

final class SessionUpdatePayloadTests: XCTestCase {
    func testTurnDetectionDisabledEncodesNull() throws {
        let config = TranscriptionSessionConfiguration(
            model: .gpt4oTranscribe,
            vadMode: .off,
            serverVAD: .init(),
            semanticVAD: .init()
        )
        let update = RealtimeTranscriptionSessionUpdate(configuration: config)
        let data = try JSONEncoder().encode(update)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let turnDetection = (((json?["session"] as? [String: Any])?["audio"] as? [String: Any])?["input"] as? [String: Any])?["turn_detection"]
        XCTAssertTrue(turnDetection is NSNull)
    }

    func testServerVADEncodesOverrides() throws {
        let config = TranscriptionSessionConfiguration(
            model: .gpt4oTranscribe,
            vadMode: .server,
            serverVAD: .init(threshold: 0.2, prefixPaddingMs: 150, silenceDurationMs: 900, idleTimeoutMs: 5000),
            semanticVAD: .init()
        )
        let update = RealtimeTranscriptionSessionUpdate(configuration: config)
        let data = try JSONEncoder().encode(update)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let input = ((json?["session"] as? [String: Any])?["audio"] as? [String: Any])?["input"] as? [String: Any]
        let turnDetection = input?["turn_detection"] as? [String: Any]
        XCTAssertEqual(turnDetection?["type"] as? String, "server_vad")
        XCTAssertEqual(turnDetection?["threshold"] as? Double, 0.2)
        XCTAssertEqual(turnDetection?["prefix_padding_ms"] as? Int, 150)
        XCTAssertEqual(turnDetection?["silence_duration_ms"] as? Int, 900)
        XCTAssertEqual(turnDetection?["idle_timeout_ms"] as? Int, 5000)
    }
}
