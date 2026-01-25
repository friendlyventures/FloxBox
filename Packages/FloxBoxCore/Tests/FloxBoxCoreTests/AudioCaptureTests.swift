@testable import FloxBoxCore
import XCTest

final class AudioCaptureTests: XCTestCase {
    func testAudioCaptureCanInitializeAndStop() {
        let capture = AudioCapture()
        capture.stop()
    }
}
