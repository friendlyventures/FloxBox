@testable import FloxBoxCore
import XCTest

final class FormattingSettingsStoreTests: XCTestCase {
    func testDefaultsPersist() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = FormattingSettingsStore(userDefaults: defaults)

        XCTAssertTrue(store.isEnabled)
        XCTAssertEqual(store.model, .gpt5Nano)

        store.isEnabled = false
        store.model = .gpt5Mini

        let reloaded = FormattingSettingsStore(userDefaults: defaults)
        XCTAssertFalse(reloaded.isEnabled)
        XCTAssertEqual(reloaded.model, .gpt5Mini)
    }
}
