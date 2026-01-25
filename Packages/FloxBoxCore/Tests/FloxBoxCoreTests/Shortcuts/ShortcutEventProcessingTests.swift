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

        let press = processor.handle(.flagsChanged(keyCode: ModifierKeyCode.rightCommand), shortcuts: [shortcut])
        XCTAssertEqual(press, [ShortcutTrigger(id: .pushToTalk, phase: .pressed)])

        let release = processor.handle(.flagsChanged(keyCode: ModifierKeyCode.rightCommand), shortcuts: [shortcut])
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

        _ = processor.handle(.flagsChanged(keyCode: ModifierKeyCode.leftOption), shortcuts: [shortcut])
        let press = processor.handle(.keyDown(keyCode: 49), shortcuts: [shortcut])
        XCTAssertEqual(press, [ShortcutTrigger(id: .pushToTalk, phase: .pressed)])

        let release = processor.handle(.keyUp(keyCode: 49), shortcuts: [shortcut])
        XCTAssertEqual(release, [ShortcutTrigger(id: .pushToTalk, phase: .released)])
    }
}
