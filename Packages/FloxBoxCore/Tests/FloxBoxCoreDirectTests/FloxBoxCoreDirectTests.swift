@testable import FloxBoxCoreDirect
import XCTest

@MainActor
final class FloxBoxCoreDirectTests: XCTestCase {
    func testDirectConfigLabel() {
        XCTAssertEqual(FloxBoxDirectServices.configuration().label, "Direct")
    }
}
