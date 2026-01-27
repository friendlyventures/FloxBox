@testable import FloxBoxCore
import SwiftUI
import XCTest

@MainActor
final class DebugPanelViewTests: XCTestCase {
    func testDebugPanelBuildsWithAPIKeyRow() {
        let model = FloxBoxAppModel.preview(configuration: .appStore)
        _ = DebugPanelView(model: model)
    }

    func testDebugPanelBuildsWithShortcutRecorder() {
        let model = FloxBoxAppModel.preview(configuration: .appStore)
        _ = DebugPanelView(model: model)
    }
}
