@testable import FloxBoxCore
import SwiftUI
import XCTest

@MainActor
final class ContentViewTests: XCTestCase {
    func testContentViewBuildsWithAPIKeyRow() {
        _ = ContentView(configuration: .appStore)
        _ = APIKeyRow(apiKey: .constant(""), status: .constant(.idle))
    }
}
