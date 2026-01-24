import XCTest
@testable import FloxBoxCore

final class FloxBoxDistributionTests: XCTestCase {
    func testAppStoreLabel() {
        XCTAssertEqual(FloxBoxDistributionConfiguration.appStore.label, "App Store")
    }

    func testAppRootCompiles() {
        _ = FloxBoxAppRoot.makeScene(configuration: .appStore)
    }
}
