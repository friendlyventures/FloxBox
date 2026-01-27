@testable import FloxBoxCore
import SwiftUI
import XCTest

@MainActor
final class MenubarMenuTests: XCTestCase {
    func testMenuBuilds() {
        let model = FloxBoxAppModel.preview(configuration: .appStore)
        _ = MenubarMenu(model: model)
    }
}
