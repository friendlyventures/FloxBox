import AppKit
import ApplicationServices
import Foundation

public protocol DictationTextInserting {
    func insert(text: String) -> Bool
}

public final class AXTextInserter: DictationTextInserting {
    private let systemElement: AXUIElement
    private let isTrusted: () -> Bool
    private let frontmostPIDProvider: () -> pid_t?
    private let applicationElementProvider: (pid_t) -> AXUIElement
    private let focusedElementProvider: (AXUIElement) -> AXUIElement?
    private let focusedWindowProvider: (AXUIElement) -> AXUIElement?
    private let valueProvider: (AXUIElement) -> String?
    private let rangeProvider: (AXUIElement) -> CFRange?
    private let valueSetter: (AXUIElement, String) -> AXError
    private let rangeSetter: (AXUIElement, CFRange) -> AXError

    public init(
        systemElement: AXUIElement = AXUIElementCreateSystemWide(),
        isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        frontmostPIDProvider: @escaping () -> pid_t? = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        },
        applicationElementProvider: @escaping (pid_t) -> AXUIElement = { AXUIElementCreateApplication($0) },
        focusedElementProvider: @escaping (AXUIElement) -> AXUIElement? = AXFocusedTextContextProvider
            .copyFocusedElement,
        focusedWindowProvider: @escaping (AXUIElement) -> AXUIElement? = AXFocusedTextContextProvider.copyFocusedWindow,
        valueProvider: @escaping (AXUIElement) -> String? = AXFocusedTextContextProvider.copyValueString,
        rangeProvider: @escaping (AXUIElement) -> CFRange? = AXFocusedTextContextProvider.copySelectedRange,
        valueSetter: @escaping (AXUIElement, String) -> AXError = { element, value in
            AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef)
        },
        rangeSetter: @escaping (AXUIElement, CFRange) -> AXError = { element, range in
            var mutableRange = range
            guard let value = AXValueCreate(.cfRange, &mutableRange) else { return .failure }
            return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
        },
    ) {
        self.systemElement = systemElement
        self.isTrusted = isTrusted
        self.frontmostPIDProvider = frontmostPIDProvider
        self.applicationElementProvider = applicationElementProvider
        self.focusedElementProvider = focusedElementProvider
        self.focusedWindowProvider = focusedWindowProvider
        self.valueProvider = valueProvider
        self.rangeProvider = rangeProvider
        self.valueSetter = valueSetter
        self.rangeSetter = rangeSetter
    }

    public func insert(text: String) -> Bool {
        guard !text.isEmpty else { return false }
        guard isTrusted() else {
            ShortcutDebugLogger.log("dictation.insert.ax notTrusted")
            return false
        }
        guard let element = resolveFocusedElement() else {
            ShortcutDebugLogger.log("dictation.insert.ax focusedElementMissing")
            return false
        }
        guard let value = valueProvider(element) else {
            ShortcutDebugLogger.log("dictation.insert.ax missingValue")
            return false
        }
        guard let range = rangeProvider(element) else {
            ShortcutDebugLogger.log("dictation.insert.ax missingRange")
            return false
        }
        guard range.location >= 0 else {
            ShortcutDebugLogger.log("dictation.insert.ax invalidRange location=\(range.location)")
            return false
        }

        let nsValue = value as NSString
        guard range.location <= nsValue.length else {
            ShortcutDebugLogger.log(
                "dictation.insert.ax rangeOutOfBounds caret=\(range.location) len=\(nsValue.length)",
            )
            return false
        }

        let selectionEnd = min(nsValue.length, range.location + max(0, range.length))
        let prefix = nsValue.substring(to: range.location)
        let suffix = nsValue.substring(from: selectionEnd)
        let newValue = prefix + text + suffix

        let valueResult = valueSetter(element, newValue)
        guard valueResult == .success else {
            ShortcutDebugLogger.log("dictation.insert.ax setValueFailed code=\(valueResult.rawValue)")
            return false
        }

        let insertedLength = (text as NSString).length
        let newCaret = range.location + insertedLength
        let rangeResult = rangeSetter(element, CFRange(location: newCaret, length: 0))
        if rangeResult != .success {
            ShortcutDebugLogger.log("dictation.insert.ax setRangeFailed code=\(rangeResult.rawValue)")
        }

        return true
    }

    private func resolveFocusedElement() -> AXUIElement? {
        if let element = focusedElementProvider(systemElement) {
            return element
        }
        guard let pid = frontmostPIDProvider() else {
            ShortcutDebugLogger.log("dictation.insert.ax fallbackNoPID")
            return nil
        }
        let appElement = applicationElementProvider(pid)
        if let element = focusedElementProvider(appElement) {
            ShortcutDebugLogger.log("dictation.insert.ax fallback=app")
            return element
        }
        guard let window = focusedWindowProvider(appElement) else {
            ShortcutDebugLogger.log("dictation.insert.ax fallbackFailed")
            return nil
        }
        guard let element = focusedElementProvider(window) else {
            ShortcutDebugLogger.log("dictation.insert.ax fallbackWindowFailed")
            return nil
        }
        ShortcutDebugLogger.log("dictation.insert.ax fallback=window")
        return element
    }
}

public final class CGEventTextInserter: DictationTextInserting {
    public init() {}

    public func insert(text: String) -> Bool {
        guard !text.isEmpty else { return false }
        guard let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { return false }
        let utf16 = Array(text.utf16)
        eventDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        eventUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        eventDown.post(tap: .cghidEventTap)
        eventUp.post(tap: .cghidEventTap)
        return true
    }
}
