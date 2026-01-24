import XCTest
@testable import FloxBoxCore

@MainActor
final class TranscriptionViewModelTests: XCTestCase {
    func testDefaults() {
        let viewModel = TranscriptionViewModel()
        XCTAssertEqual(viewModel.model, .defaultModel)
        XCTAssertEqual(viewModel.vadMode, .server)
        XCTAssertEqual(viewModel.manualCommitInterval, .defaultInterval)
        XCTAssertEqual(viewModel.status, .idle)
        XCTAssertEqual(viewModel.transcript, "")
    }
}
