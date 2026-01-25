import Foundation

public enum ShortcutID: String, Codable, CaseIterable, Sendable {
    case pushToTalk
}

public enum ShortcutBehavior: String, Codable, Sendable {
    case pushToTalk
    case toggle
}

public struct ModifierSet: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let leftShift = ModifierSet(rawValue: 1 << 0)
    public static let rightShift = ModifierSet(rawValue: 1 << 1)
    public static let leftControl = ModifierSet(rawValue: 1 << 2)
    public static let rightControl = ModifierSet(rawValue: 1 << 3)
    public static let leftOption = ModifierSet(rawValue: 1 << 4)
    public static let rightOption = ModifierSet(rawValue: 1 << 5)
    public static let leftCommand = ModifierSet(rawValue: 1 << 6)
    public static let rightCommand = ModifierSet(rawValue: 1 << 7)

    public var displayString: String {
        var parts: [String] = []
        if contains(.leftControl) { parts.append("⌃L") }
        if contains(.rightControl) { parts.append("⌃R") }
        if contains(.leftOption) { parts.append("⌥L") }
        if contains(.rightOption) { parts.append("⌥R") }
        if contains(.leftShift) { parts.append("⇧L") }
        if contains(.rightShift) { parts.append("⇧R") }
        if contains(.leftCommand) { parts.append("⌘L") }
        if contains(.rightCommand) { parts.append("⌘R") }
        return parts.joined(separator: " ")
    }
}

public struct ShortcutDefinition: Codable, Hashable, Identifiable, Sendable {
    public let id: ShortcutID
    public var name: String
    public var keyCode: UInt16?
    public var modifiers: ModifierSet
    public var behavior: ShortcutBehavior

    public init(
        id: ShortcutID,
        name: String,
        keyCode: UInt16?,
        modifiers: ModifierSet,
        behavior: ShortcutBehavior,
    ) {
        self.id = id
        self.name = name
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.behavior = behavior
    }

    public var isEmpty: Bool {
        keyCode == nil && modifiers.isEmpty
    }

    public var displayString: String {
        let key = keyCode.map(KeyCodeDisplay.name(for:)) ?? ""
        let parts = [modifiers.displayString, key].filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }
}

private enum KeyCodeDisplay {
    static func name(for keyCode: UInt16) -> String {
        switch keyCode {
        case 49:
            "Space"
        case 36:
            "Return"
        case 53:
            "Escape"
        default:
            "Key \(keyCode)"
        }
    }
}
