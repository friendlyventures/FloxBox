import SwiftUI
import XCTest
@testable import FloxBoxCore

@MainActor
final class ContentViewTests: XCTestCase {
    func testContentViewBuildsWithAPIKeyRow() {
        _ = ContentView(configuration: .appStore)
        _ = APIKeyRow(apiKey: .constant(""), status: .constant(.idle))
    }
}
