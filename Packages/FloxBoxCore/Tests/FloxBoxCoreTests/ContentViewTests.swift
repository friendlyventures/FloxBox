import SwiftUI
import XCTest
@testable import FloxBoxCore

@MainActor
final class ContentViewTests: XCTestCase {
    func testContentViewAndHelpersBuild() {
        _ = ContentView(configuration: .appStore)
        _ = OptionalDoubleField(title: "Threshold", value: .constant(nil as Double?))
        _ = OptionalIntField(title: "Prefix", value: .constant(nil as Int?))
    }
}
