import XCTest
@testable import FloxBoxCore

final class TranscriptionConfigTests: XCTestCase {
    func testModelListIsExact() {
        XCTAssertEqual(
            TranscriptionModel.allCases.map(\.rawValue),
            [
                "gpt-4o-transcribe",
                "gpt-4o-transcribe-latest",
                "gpt-4o-mini-transcribe",
                "gpt-4o-mini-transcribe-2025-12-15",
                "whisper-1",
            ]
        )
    }

    func testDefaultModel() {
        XCTAssertEqual(TranscriptionModel.defaultModel, .gpt4oTranscribe)
    }

    func testManualCommitIntervalOptions() {
        XCTAssertEqual(
            ManualCommitInterval.options,
            [
                .off,
                .seconds(1),
                .seconds(2),
                .seconds(3),
                .seconds(4),
                .seconds(5),
            ]
        )
        XCTAssertEqual(ManualCommitInterval.defaultInterval, .seconds(2))
    }
}
