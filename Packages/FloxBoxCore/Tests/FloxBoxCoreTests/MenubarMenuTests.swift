@testable import FloxBoxCore
import SwiftUI
import XCTest

@MainActor
final class MenubarMenuTests: XCTestCase {
    func testMenuBuilds() {
        let model = FloxBoxAppModel.preview(configuration: .appStore)
        _ = MenubarMenu(model: model)
    }

    func testMenuBuildsWithUpdatesAction() {
        let config = FloxBoxDistributionConfiguration(label: "Direct", checkForUpdates: {})
        let model = FloxBoxAppModel.preview(configuration: config)
        let menu = MenubarMenu(model: model)
        XCTAssertTrue(menu.hasCheckForUpdatesAction)
    }
}
