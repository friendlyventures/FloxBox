@testable import FloxBoxCore
import XCTest

final class SessionUpdatePayloadTests: XCTestCase {
    func testTurnDetectionDisabledEncodesNull() throws {
        let config = TranscriptionSessionConfiguration(
            model: .gpt4oTranscribe,
            language: .english,
            vadMode: .off,
            serverVAD: .init(),
            semanticVAD: .init(),
        )
        let update = RealtimeTranscriptionSessionUpdate(configuration: config)
        let data = try JSONEncoder().encode(update)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let turnDetection = (json?["session"] as? [String: Any])?["turn_detection"]
        XCTAssertTrue(turnDetection is NSNull)
    }

    func testServerVADEncodesOverrides() throws {
        let config = TranscriptionSessionConfiguration(
            model: .gpt4oTranscribe,
            language: .english,
            vadMode: .server,
            serverVAD: .init(threshold: 0.2, prefixPaddingMs: 150, silenceDurationMs: 900, idleTimeoutMs: 5000),
            semanticVAD: .init(),
        )
        let update = RealtimeTranscriptionSessionUpdate(configuration: config)
        let data = try JSONEncoder().encode(update)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let session = json?["session"] as? [String: Any]
        let turnDetection = session?["turn_detection"] as? [String: Any]
        XCTAssertEqual(turnDetection?["type"] as? String, "server_vad")
        XCTAssertEqual(turnDetection?["threshold"] as? Double, 0.2)
        XCTAssertEqual(turnDetection?["prefix_padding_ms"] as? Int, 150)
        XCTAssertEqual(turnDetection?["silence_duration_ms"] as? Int, 900)
        XCTAssertEqual(turnDetection?["idle_timeout_ms"] as? Int, 5000)
    }

    func testLanguageEncodesISOCode() throws {
        let config = TranscriptionSessionConfiguration(
            model: .gpt4oTranscribe,
            language: .german,
            vadMode: .off,
            serverVAD: .init(),
            semanticVAD: .init(),
        )
        let update = RealtimeTranscriptionSessionUpdate(configuration: config)
        let data = try JSONEncoder().encode(update)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let session = json?["session"] as? [String: Any]
        let transcription = session?["input_audio_transcription"] as? [String: Any]
        XCTAssertEqual(transcription?["language"] as? String, "de")
    }

    func testNoiseReductionEncodesType() throws {
        let config = TranscriptionSessionConfiguration(
            model: .gpt4oTranscribe,
            language: .english,
            noiseReduction: .nearField,
            vadMode: .off,
            serverVAD: .init(),
            semanticVAD: .init(),
        )
        let update = RealtimeTranscriptionSessionUpdate(configuration: config)
        let data = try JSONEncoder().encode(update)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let session = json?["session"] as? [String: Any]
        let reduction = session?["input_audio_noise_reduction"] as? [String: Any]
        XCTAssertEqual(reduction?["type"] as? String, "near_field")
    }

    func testNoiseReductionOffOmitsField() throws {
        let config = TranscriptionSessionConfiguration(
            model: .gpt4oTranscribe,
            language: .english,
            noiseReduction: nil,
            vadMode: .off,
            serverVAD: .init(),
            semanticVAD: .init(),
        )
        let update = RealtimeTranscriptionSessionUpdate(configuration: config)
        let data = try JSONEncoder().encode(update)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let session = json?["session"] as? [String: Any]
        XCTAssertNil(session?["input_audio_noise_reduction"])
    }
}
