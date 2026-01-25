@testable import FloxBoxCore
import XCTest

@MainActor
final class ShortcutStoreTests: XCTestCase {
    func testDefaultsToRightCommandPushToTalkWhenNoStoredData() {
        let suite = "ShortcutStoreDefaults"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let store = ShortcutStore(userDefaults: defaults)
        let shortcut = store.shortcut(for: .pushToTalk)

        XCTAssertEqual(shortcut?.modifiers, [.rightCommand])
        XCTAssertNil(shortcut?.keyCode)
        XCTAssertEqual(shortcut?.behavior, .pushToTalk)
        XCTAssertEqual(shortcut?.name, "Push To Talk")
    }

    func testUpsertReplacesExistingShortcut() {
        let store = ShortcutStore(userDefaults: UserDefaults(suiteName: "ShortcutStoreTests")!)
        let original = ShortcutDefinition(
            id: .pushToTalk,
            name: "Push To Talk",
            keyCode: 49,
            modifiers: [.leftOption],
            behavior: .pushToTalk,
        )
        let updated = ShortcutDefinition(
            id: .pushToTalk,
            name: "Push To Talk",
            keyCode: 49,
            modifiers: [.rightCommand],
            behavior: .pushToTalk,
        )

        store.upsert(original)
        store.upsert(updated)

        XCTAssertEqual(store.shortcuts.count, 1)
        XCTAssertEqual(store.shortcut(for: .pushToTalk), updated)
    }

    func testPersistenceRoundTrip() throws {
        let suite = "ShortcutStoreTestsRoundTrip"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let shortcut = ShortcutDefinition(
            id: .pushToTalk,
            name: "Push To Talk",
            keyCode: 49,
            modifiers: [.leftOption, .rightCommand],
            behavior: .pushToTalk,
        )

        let store = ShortcutStore(userDefaults: defaults)
        store.upsert(shortcut)

        let reloaded = ShortcutStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.shortcut(for: .pushToTalk), shortcut)
    }
}
