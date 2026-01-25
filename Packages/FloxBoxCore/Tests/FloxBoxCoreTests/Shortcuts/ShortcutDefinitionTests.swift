@testable import FloxBoxCore
import XCTest

final class ShortcutDefinitionTests: XCTestCase {
    func testShortcutRoundTripKeepsLeftRightModifiers() throws {
        let shortcut = ShortcutDefinition(
            id: .pushToTalk,
            name: "Push To Talk",
            keyCode: 49,
            modifiers: [.leftOption, .rightCommand],
            behavior: .pushToTalk,
        )

        let data = try JSONEncoder().encode(shortcut)
        let decoded = try JSONDecoder().decode(ShortcutDefinition.self, from: data)

        XCTAssertEqual(decoded, shortcut)
    }

    func testDisplayStringIncludesModifierSidesAndKey() {
        let shortcut = ShortcutDefinition(
            id: .pushToTalk,
            name: "Push To Talk",
            keyCode: 49,
            modifiers: [.leftOption, .rightCommand],
            behavior: .pushToTalk,
        )

        XCTAssertEqual(shortcut.displayString, "⌥L ⌘R Space")
    }
}
