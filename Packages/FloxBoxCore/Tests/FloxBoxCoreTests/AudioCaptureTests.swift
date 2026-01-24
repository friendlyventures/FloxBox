import XCTest
@testable import FloxBoxCore

final class AudioCaptureTests: XCTestCase {
    func testAudioCaptureCanInitializeAndStop() {
        let capture = AudioCapture()
        capture.stop()
    }
}
