@testable import FloxBoxCore
import XCTest

final class LoggingAvailabilityTests: XCTestCase {
    func testShortcutDebugLoggerIsEnabled() {
        XCTAssertTrue(ShortcutDebugLogger.isEnabled)
    }

    func testDebugLogIsEnabled() {
        XCTAssertTrue(DebugLog.isEnabled)
    }
}
