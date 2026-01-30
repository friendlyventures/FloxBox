@testable import FloxBoxCore
import XCTest

final class FormatValidatorTests: XCTestCase {
    func testValidatorAcceptsMinorFormattingChanges() {
        let validator = FormatValidator()
        XCTAssertTrue(validator.isAcceptable(
            original: "Open AI makes models",
            formatted: "OpenAI makes models.",
        ))
    }

    func testValidatorRejectsMajorChanges() {
        let validator = FormatValidator()
        XCTAssertFalse(validator.isAcceptable(
            original: "Open AI makes models",
            formatted: "We should go to the store.",
        ))
    }
}
