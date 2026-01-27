import Foundation

public enum ShortcutEvent: Equatable {
    case keyDown(keyCode: UInt16)
    case keyUp(keyCode: UInt16)
    case flagsChanged(keyCode: UInt16, isDown: Bool)
}

public enum ShortcutTriggerPhase: Equatable {
    case pressed
    case released
}

public struct ShortcutTrigger: Equatable {
    public let id: ShortcutID
    public let phase: ShortcutTriggerPhase
}

public enum ModifierKeyCode {
    public static let leftShift: UInt16 = 56
    public static let rightShift: UInt16 = 60
    public static let leftControl: UInt16 = 59
    public static let rightControl: UInt16 = 62
    public static let leftOption: UInt16 = 58
    public static let rightOption: UInt16 = 61
    public static let leftCommand: UInt16 = 55
    public static let rightCommand: UInt16 = 54

    public static func modifier(for keyCode: UInt16) -> ModifierSet? {
        switch keyCode {
        case leftShift: .leftShift
        case rightShift: .rightShift
        case leftControl: .leftControl
        case rightControl: .rightControl
        case leftOption: .leftOption
        case rightOption: .rightOption
        case leftCommand: .leftCommand
        case rightCommand: .rightCommand
        default: nil
        }
    }
}

struct ChordState: Equatable {
    var modifiers: ModifierSet = []
    var pressedKeyCode: UInt16?

    var isEmpty: Bool {
        pressedKeyCode == nil && modifiers.isEmpty
    }

    mutating func apply(_ event: ShortcutEvent) {
        switch event {
        case let .flagsChanged(keyCode, isDown):
            guard let modifier = ModifierKeyCode.modifier(for: keyCode) else { return }
            if isDown {
                modifiers.insert(modifier)
            } else {
                modifiers.remove(modifier)
            }
        case let .keyDown(keyCode):
            pressedKeyCode = keyCode
        case let .keyUp(keyCode):
            if pressedKeyCode == keyCode {
                pressedKeyCode = nil
            }
        }
    }
}

public struct ShortcutEventProcessor {
    private var state = ChordState()
    private var activeShortcuts: Set<ShortcutID> = []

    public init() {}

    var currentState: ChordState { state }

    public mutating func handle(_ event: ShortcutEvent, shortcuts: [ShortcutDefinition]) -> [ShortcutTrigger] {
        state.apply(event)

        let currentlyActive = Set(shortcuts.filter { matches($0) }.map(\.id))
        let pressed = currentlyActive.subtracting(activeShortcuts)
        let released = activeShortcuts.subtracting(currentlyActive)

        activeShortcuts = currentlyActive

        return pressed.map { ShortcutTrigger(id: $0, phase: .pressed) }
            + released.map { ShortcutTrigger(id: $0, phase: .released) }
    }

    private func matches(_ shortcut: ShortcutDefinition) -> Bool {
        if shortcut.modifiers != state.modifiers { return false }
        switch shortcut.keyCode {
        case nil:
            return true
        case let keyCode:
            return state.pressedKeyCode == keyCode
        }
    }
}
