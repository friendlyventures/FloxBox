import XCTest
@testable import FloxBoxCoreDirect

final class FloxBoxCoreDirectTests: XCTestCase {
    func testDirectConfigLabel() {
        XCTAssertEqual(FloxBoxDirectServices.configuration().label, "Direct")
    }
}
