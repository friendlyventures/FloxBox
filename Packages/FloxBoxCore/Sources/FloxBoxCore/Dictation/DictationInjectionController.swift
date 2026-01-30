import AppKit
import Carbon
import CoreGraphics

public protocol DictationUpdateCoalescing {
    func enqueue(_ text: String, flush: @escaping (String) -> Void)
    func flush()
    func cancel()
}

public protocol DictationEventPosting {
    func postBackspaces(_ count: Int) -> Bool
    func postText(_ text: String) -> Bool
}

@MainActor
public protocol DictationInjectionControlling {
    func startSession()
    func apply(text: String)
    func insertFinal(text: String) -> Bool
    func finishSession() -> DictationInjectionResult
}

public struct DictationInjectionResult: Equatable {
    public let requiresManualPaste: Bool

    public var requiresClipboardFallback: Bool {
        requiresManualPaste
    }
}

@MainActor
public final class DictationInjectionController {
    public nonisolated static let defaultClipboardPreferredBundleIdentifiers: Set<String> = [
        "com.mitchellh.ghostty",
    ]

    private let inserter: DictationTextInserting
    private let fallbackInserter: DictationTextInserting
    private let focusedTextContextProvider: FocusedTextContextProviding
    private let frontmostAppProvider: () -> String?
    private let bundleIdentifier: String
    private let clipboardPreferredBundleIdentifiers: Set<String>

    private var lastInjected = ""
    private var didInject = false
    private var didFail = false
    private var sessionPrefix: String?
    private var lastFrontmostApp: String?
    private var lastSessionInjectedText: String?
    private var lastSessionFrontmostApp: String?

    public init(
        inserter: DictationTextInserting = AXTextInserter(),
        fallbackInserter: DictationTextInserting = ClipboardTextInserter(),
        focusedTextContextProvider: FocusedTextContextProviding = AXFocusedTextContextProvider(),
        frontmostAppProvider: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "",
        clipboardPreferredBundleIdentifiers: Set<String> = DictationInjectionController
            .defaultClipboardPreferredBundleIdentifiers,
    ) {
        self.inserter = inserter
        self.fallbackInserter = fallbackInserter
        self.focusedTextContextProvider = focusedTextContextProvider
        self.frontmostAppProvider = frontmostAppProvider
        self.bundleIdentifier = bundleIdentifier
        self.clipboardPreferredBundleIdentifiers = clipboardPreferredBundleIdentifiers
    }

    public func startSession() {
        ShortcutDebugLogger.log("dictation.startSession")
        lastInjected = ""
        didInject = false
        didFail = false
        sessionPrefix = nil
    }

    public func apply(text: String) {
        ShortcutDebugLogger.log("dictation.apply ignored len=\(text.count)")
    }

    @discardableResult
    public func insertFinal(text: String) -> Bool {
        guard !text.isEmpty else { return false }
        ShortcutDebugLogger.log("dictation.insert.start len=\(text.count)")
        let frontmost = frontmostAppProvider()
        lastFrontmostApp = frontmost
        ShortcutDebugLogger.log("dictation.insert frontmost=\(frontmost ?? "nil")")
        if frontmost == bundleIdentifier {
            ShortcutDebugLogger.log("dictation.insert blocked frontmost=\(frontmost ?? "nil")")
            didFail = true
            return false
        }

        let resolved = resolvedText(for: text)
        if let frontmost, clipboardPreferredBundleIdentifiers.contains(frontmost) {
            ShortcutDebugLogger.log("dictation.insert preferClipboard frontmost=\(frontmost)")
            if fallbackInserter.insert(text: resolved) {
                ShortcutDebugLogger.log("dictation.insert.cg.success len=\(resolved.count)")
                lastInjected = resolved
                didInject = true
                return true
            }
            ShortcutDebugLogger.log("dictation.insert.cg.fail")
            didFail = true
            return false
        }
        if inserter.insert(text: resolved) {
            ShortcutDebugLogger.log("dictation.insert.ax.success len=\(resolved.count)")
            lastInjected = resolved
            didInject = true
            return true
        }
        ShortcutDebugLogger.log("dictation.insert.ax.fail")

        if fallbackInserter.insert(text: resolved) {
            ShortcutDebugLogger.log("dictation.insert.cg.success len=\(resolved.count)")
            lastInjected = resolved
            didInject = true
            return true
        }
        ShortcutDebugLogger.log("dictation.insert.cg.fail")
        didFail = true
        return false
    }

    public func finishSession() -> DictationInjectionResult {
        if didInject {
            lastSessionInjectedText = lastInjected
            lastSessionFrontmostApp = lastFrontmostApp
        } else {
            lastSessionInjectedText = nil
            lastSessionFrontmostApp = nil
        }
        let result = DictationInjectionResult(requiresManualPaste: didFail || !didInject)
        let finishMessage = "dictation.finish didInject=\(didInject) didFail=\(didFail) "
            + "requiresManualPaste=\(result.requiresManualPaste)"
        ShortcutDebugLogger.log(finishMessage)
        return result
    }

    private func resolvedText(for text: String) -> String {
        if text.isEmpty {
            return text
        }
        if sessionPrefix == nil {
            sessionPrefix = determinePrefix(for: text)
        }
        return (sessionPrefix ?? "") + text
    }

    private func determinePrefix(for text: String) -> String {
        guard !text.isEmpty else { return "" }
        let firstScalar = text.unicodeScalars.first
        let startsWithWhitespace = firstScalar.map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false
        let startsWithPunct = firstScalar.map { CharacterSet.punctuationCharacters.contains($0) } ?? false
        let prefixMeta = "dictation.prefix textLen=\(text.count) "
            + "startsWhitespace=\(startsWithWhitespace) startsPunct=\(startsWithPunct)"
        ShortcutDebugLogger.log(prefixMeta)
        if startsWithWhitespace || startsWithPunct {
            ShortcutDebugLogger.log("dictation.prefix decision=empty reason=startChar")
            return ""
        }

        guard let context = focusedTextContextProvider.focusedTextContext() else {
            let fallback = fallbackPrefix(for: text)
            if fallback.isEmpty {
                ShortcutDebugLogger.log("dictation.prefix decision=empty reason=noContext")
            } else {
                ShortcutDebugLogger.log("dictation.prefix decision=space reason=fallback")
            }
            return fallback
        }
        guard context.caretIndex > 0 else {
            ShortcutDebugLogger.log("dictation.prefix decision=empty reason=caretStart")
            return ""
        }
        let nsValue = context.value as NSString
        guard context.caretIndex <= nsValue.length else {
            ShortcutDebugLogger.log(
                "dictation.prefix decision=empty reason=caretOob caret=\(context.caretIndex) len=\(nsValue.length)",
            )
            return ""
        }
        let preceding = nsValue.character(at: context.caretIndex - 1)
        guard let scalar = UnicodeScalar(preceding) else {
            ShortcutDebugLogger.log("dictation.prefix decision=empty reason=precedingInvalid")
            return ""
        }
        if CharacterSet.whitespacesAndNewlines.contains(scalar) {
            ShortcutDebugLogger.log("dictation.prefix decision=empty reason=precedingWhitespace")
            return ""
        }
        ShortcutDebugLogger.log("dictation.prefix decision=space")
        return " "
    }

    private func fallbackPrefix(for _: String) -> String {
        guard let lastText = lastSessionInjectedText, !lastText.isEmpty else { return "" }
        guard let lastApp = lastSessionFrontmostApp else { return "" }
        guard let currentApp = frontmostAppProvider(), currentApp == lastApp else { return "" }
        guard let scalar = lastText.unicodeScalars.last else { return "" }
        if CharacterSet.whitespacesAndNewlines.contains(scalar) {
            return ""
        }
        return " "
    }
}

extension DictationInjectionController: DictationInjectionControlling {}

public final class CGEventPoster: DictationEventPosting {
    public init() {}

    public func postBackspaces(_ count: Int) -> Bool {
        guard count > 0 else { return true }
        for _ in 0 ..< count {
            postKeyDownUp(keyCode: CGKeyCode(kVK_Delete))
        }
        return true
    }

    public func postText(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        guard let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { return false }
        let utf16 = Array(text.utf16)
        eventDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        eventUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        eventDown.post(tap: .cghidEventTap)
        eventUp.post(tap: .cghidEventTap)
        return true
    }

    private func postKeyDownUp(keyCode: CGKeyCode) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
