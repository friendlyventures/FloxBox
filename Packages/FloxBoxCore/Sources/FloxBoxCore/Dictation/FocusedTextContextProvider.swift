import AppKit
import ApplicationServices
import Foundation

public struct FocusedTextContext: Equatable {
    public let value: String
    public let caretIndex: Int

    public init(value: String, caretIndex: Int) {
        self.value = value
        self.caretIndex = caretIndex
    }
}

public protocol FocusedTextContextProviding {
    func focusedTextContext() -> FocusedTextContext?
}

public struct NoopFocusedTextContextProvider: FocusedTextContextProviding {
    public init() {}

    public func focusedTextContext() -> FocusedTextContext? {
        nil
    }
}

public struct AXFocusedTextContextProvider: FocusedTextContextProviding {
    private let systemElement: AXUIElement
    private let isTrusted: () -> Bool
    private let frontmostPIDProvider: () -> pid_t?
    private let applicationElementProvider: (pid_t) -> AXUIElement
    private let focusedElementProvider: (AXUIElement) -> AXUIElement?
    private let focusedWindowProvider: (AXUIElement) -> AXUIElement?
    private let valueProvider: (AXUIElement) -> String?
    private let rangeProvider: (AXUIElement) -> CFRange?
    private let secureElementProvider: (AXUIElement) -> Bool

    public init(
        systemElement: AXUIElement = AXUIElementCreateSystemWide(),
        isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        frontmostPIDProvider: @escaping () -> pid_t? = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        },
        applicationElementProvider: @escaping (pid_t) -> AXUIElement = { AXUIElementCreateApplication($0) },
        focusedElementProvider: @escaping (AXUIElement) -> AXUIElement? = AXFocusedTextContextProvider
            .copyFocusedElement,
        focusedWindowProvider: @escaping (AXUIElement) -> AXUIElement? = AXFocusedTextContextProvider
            .copyFocusedWindow,
        valueProvider: @escaping (AXUIElement) -> String? = AXFocusedTextContextProvider.copyValueString,
        rangeProvider: @escaping (AXUIElement) -> CFRange? = AXFocusedTextContextProvider.copySelectedRange,
        secureElementProvider: @escaping (AXUIElement) -> Bool = AXFocusedTextContextProvider.isSecureTextElement,
    ) {
        self.systemElement = systemElement
        self.isTrusted = isTrusted
        self.frontmostPIDProvider = frontmostPIDProvider
        self.applicationElementProvider = applicationElementProvider
        self.focusedElementProvider = focusedElementProvider
        self.focusedWindowProvider = focusedWindowProvider
        self.valueProvider = valueProvider
        self.rangeProvider = rangeProvider
        self.secureElementProvider = secureElementProvider
    }

    public func focusedTextContext() -> FocusedTextContext? {
        guard isTrusted() else {
            ShortcutDebugLogger.log("peek.ax notTrusted")
            return nil
        }

        guard let element = resolveFocusedElement() else {
            ShortcutDebugLogger.log("peek.ax focusedElementMissing")
            return nil
        }

        if secureElementProvider(element) {
            ShortcutDebugLogger.log("peek.ax secureField")
            return nil
        }
        guard let value = valueProvider(element) else {
            ShortcutDebugLogger.log("peek.ax missingValue")
            return nil
        }
        guard let range = rangeProvider(element) else {
            ShortcutDebugLogger.log("peek.ax missingRange")
            return nil
        }
        guard range.location >= 0 else {
            ShortcutDebugLogger.log("peek.ax invalidRange location=\(range.location)")
            return nil
        }
        let nsValue = value as NSString
        guard range.location <= nsValue.length else {
            ShortcutDebugLogger.log(
                "peek.ax rangeOutOfBounds caret=\(range.location) len=\(nsValue.length)",
            )
            return nil
        }
        ShortcutDebugLogger.log("peek.ax ok len=\(nsValue.length) caret=\(range.location)")
        return FocusedTextContext(value: value, caretIndex: range.location)
    }

    private func resolveFocusedElement() -> AXUIElement? {
        if let element = focusedElementProvider(systemElement) {
            return element
        }
        guard let pid = frontmostPIDProvider() else {
            ShortcutDebugLogger.log("peek.ax fallbackNoPID")
            return nil
        }
        let appElement = applicationElementProvider(pid)
        if let element = focusedElementProvider(appElement) {
            ShortcutDebugLogger.log("peek.ax fallback=app")
            return element
        }
        guard let window = focusedWindowProvider(appElement) else {
            ShortcutDebugLogger.log("peek.ax fallbackFailed")
            return nil
        }
        guard let element = focusedElementProvider(window) else {
            ShortcutDebugLogger.log("peek.ax fallbackWindowFailed")
            return nil
        }
        ShortcutDebugLogger.log("peek.ax fallback=window")
        return element
    }

    public static func copyFocusedElement(from root: AXUIElement) -> AXUIElement? {
        var focused: AnyObject?
        let result = AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &focused)
        guard result == .success, let focused else {
            ShortcutDebugLogger.log("peek.ax focusedElementMissing result=\(result.rawValue)")
            return nil
        }
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            ShortcutDebugLogger.log("peek.ax focusedElementWrongType")
            return nil
        }
        return unsafeBitCast(focused, to: AXUIElement.self)
    }

    public static func copyFocusedWindow(from root: AXUIElement) -> AXUIElement? {
        if let window = copyWindow(from: root, attribute: kAXFocusedWindowAttribute as CFString) {
            return window
        }
        return copyWindow(from: root, attribute: kAXMainWindowAttribute as CFString)
    }

    private static func copyWindow(from root: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(root, attribute, &value)
        guard result == .success, let value else {
            ShortcutDebugLogger.log("peek.ax windowMissing result=\(result.rawValue)")
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            ShortcutDebugLogger.log("peek.ax windowWrongType")
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    public static func copyValueString(_ element: AXUIElement) -> String? {
        copyString(element, attribute: kAXValueAttribute as CFString)
    }

    public static func copySelectedRange(_ element: AXUIElement) -> CFRange? {
        copyRange(element, attribute: kAXSelectedTextRangeAttribute as CFString)
    }

    static func copyString(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        if let string = value as? String {
            return string
        }
        if let attributed = value as? NSAttributedString {
            ShortcutDebugLogger.log("peek.ax valueIsAttributedString len=\(attributed.string.count)")
        } else if value != nil {
            ShortcutDebugLogger.log("peek.ax valueNotString type=\(type(of: value!))")
        }
        return nil
    }

    static func copyRange(_ element: AXUIElement, attribute: CFString) -> CFRange? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        guard let value else { return nil }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    public static func isSecureTextElement(_ element: AXUIElement) -> Bool {
        guard let subrole = copyString(element, attribute: kAXSubroleAttribute as CFString) else { return false }
        return subrole == (kAXSecureTextFieldSubrole as String)
    }
}
