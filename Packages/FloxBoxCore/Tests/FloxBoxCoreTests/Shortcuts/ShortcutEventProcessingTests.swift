@testable import FloxBoxCore
import XCTest

final class ShortcutEventProcessingTests: XCTestCase {
    func testModifierOnlyShortcutTriggersOnPressAndRelease() {
        var processor = ShortcutEventProcessor()
        let shortcut = ShortcutDefinition(
            id: .pushToTalk,
            name: "Push To Talk",
            keyCode: nil,
            modifiers: [.rightCommand],
            behavior: .pushToTalk,
        )

        let press = processor.handle(
            .flagsChanged(keyCode: ModifierKeyCode.rightCommand, isDown: true),
            shortcuts: [shortcut],
        )
        XCTAssertEqual(press, [ShortcutTrigger(id: .pushToTalk, phase: .pressed)])

        let release = processor.handle(
            .flagsChanged(keyCode: ModifierKeyCode.rightCommand, isDown: false),
            shortcuts: [shortcut],
        )
        XCTAssertEqual(release, [ShortcutTrigger(id: .pushToTalk, phase: .released)])
    }

    func testChordShortcutTriggersOnKeyDownAndKeyUp() {
        var processor = ShortcutEventProcessor()
        let shortcut = ShortcutDefinition(
            id: .pushToTalk,
            name: "Push To Talk",
            keyCode: 49,
            modifiers: [.leftOption],
            behavior: .pushToTalk,
        )

        _ = processor.handle(
            .flagsChanged(keyCode: ModifierKeyCode.leftOption, isDown: true),
            shortcuts: [shortcut],
        )
        let press = processor.handle(.keyDown(keyCode: 49), shortcuts: [shortcut])
        XCTAssertEqual(press, [ShortcutTrigger(id: .pushToTalk, phase: .pressed)])

        let release = processor.handle(.keyUp(keyCode: 49), shortcuts: [shortcut])
        XCTAssertEqual(release, [ShortcutTrigger(id: .pushToTalk, phase: .released)])
    }

    func testModifierOnlyShortcutIgnoresNonModifierKeysWhileHeld() {
        var processor = ShortcutEventProcessor()
        let shortcut = ShortcutDefinition(
            id: .pushToTalk,
            name: "Push To Talk",
            keyCode: nil,
            modifiers: [.rightCommand],
            behavior: .pushToTalk,
        )

        let press = processor.handle(
            .flagsChanged(keyCode: ModifierKeyCode.rightCommand, isDown: true),
            shortcuts: [shortcut],
        )
        XCTAssertEqual(press, [ShortcutTrigger(id: .pushToTalk, phase: .pressed)])

        let nonModifierDown = processor.handle(.keyDown(keyCode: 0), shortcuts: [shortcut])
        XCTAssertEqual(nonModifierDown, [])

        let nonModifierUp = processor.handle(.keyUp(keyCode: 0), shortcuts: [shortcut])
        XCTAssertEqual(nonModifierUp, [])

        let release = processor.handle(
            .flagsChanged(keyCode: ModifierKeyCode.rightCommand, isDown: false),
            shortcuts: [shortcut],
        )
        XCTAssertEqual(release, [ShortcutTrigger(id: .pushToTalk, phase: .released)])
    }
}
