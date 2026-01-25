@testable import FloxBoxCoreDirect
import XCTest

final class FloxBoxCoreDirectTests: XCTestCase {
    func testDirectConfigLabel() {
        XCTAssertEqual(FloxBoxDirectServices.configuration().label, "Direct")
    }
}
