@testable import FloxBoxCore
import XCTest

@MainActor
final class FloxBoxDistributionTests: XCTestCase {
    func testAppStoreLabel() {
        XCTAssertEqual(FloxBoxDistributionConfiguration.appStore.label, "App Store")
    }

    func testAppRootCompiles() {
        let model = FloxBoxAppModel.preview(configuration: .appStore)
        _ = FloxBoxAppRoot.makeScene(model: model)
    }
}
