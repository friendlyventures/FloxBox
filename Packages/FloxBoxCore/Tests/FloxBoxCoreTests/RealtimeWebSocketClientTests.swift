@testable import FloxBoxCore
import XCTest

final class RealtimeWebSocketClientTests: XCTestCase {
    func testClientInitializes() {
        let client = RealtimeWebSocketClient(apiKey: "test-key")
        _ = client.events
    }

    func testBaseURLUsesWss() {
        XCTAssertEqual(RealtimeAPI.baseURL.scheme, "wss")
    }
}
