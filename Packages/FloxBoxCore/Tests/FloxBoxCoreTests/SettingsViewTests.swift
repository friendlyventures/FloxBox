@testable import FloxBoxCore
import SwiftUI
import XCTest

@MainActor
final class SettingsViewTests: XCTestCase {
    func testSettingsBuildsWithAPIKeyRow() {
        let model = FloxBoxAppModel.preview(configuration: .appStore)
        _ = SettingsView(model: model)
    }
}
