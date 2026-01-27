@testable import FloxBoxCore
import XCTest

final class NotchRecordingViewTests: XCTestCase {
    @MainActor
    func testNotchRecordingViewBuildsInAwaitingNetworkState() {
        let state = NotchRecordingState()
        state.isRecording = false
        state.isAwaitingNetwork = true
        state.showNetworkSpinner = true
        _ = NotchRecordingView(state: state)
    }
}
