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
    func finishSession() -> DictationInjectionResult
}

public struct DictationInjectionResult: Equatable {
    public let requiresClipboardFallback: Bool
}

@MainActor
public final class DictationInjectionController {
    private let eventPoster: DictationEventPosting
    private let coalescer: DictationUpdateCoalescing
    private let focusedTextContextProvider: FocusedTextContextProviding
    private let frontmostAppProvider: () -> String?
    private let bundleIdentifier: String

    private var lastInjected = ""
    private var didInject = false
    private var didFail = false
    private var sessionPrefix: String?
    private var lastFrontmostApp: String?
    private var lastSessionInjectedText: String?
    private var lastSessionFrontmostApp: String?

    public init(
        eventPoster: DictationEventPosting = CGEventPoster(),
        coalescer: DictationUpdateCoalescing = DictationUpdateCoalescer(interval: 0.08),
        focusedTextContextProvider: FocusedTextContextProviding = AXFocusedTextContextProvider(),
        frontmostAppProvider: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "",
    ) {
        self.eventPoster = eventPoster
        self.coalescer = coalescer
        self.focusedTextContextProvider = focusedTextContextProvider
        self.frontmostAppProvider = frontmostAppProvider
        self.bundleIdentifier = bundleIdentifier
    }

    public func startSession() {
        ShortcutDebugLogger.log("dictation.startSession")
        lastInjected = ""
        didInject = false
        didFail = false
        sessionPrefix = nil
        coalescer.cancel()
    }

    public func apply(text: String) {
        ShortcutDebugLogger.log("dictation.apply len=\(text.count)")
        let resolved = resolvedText(for: text)
        coalescer.enqueue(resolved) { [weak self] in
            self?.flush(text: $0)
        }
    }

    public func finishSession() -> DictationInjectionResult {
        coalescer.flush()
        coalescer.cancel()
        if didInject {
            lastSessionInjectedText = lastInjected
            lastSessionFrontmostApp = lastFrontmostApp
        } else {
            lastSessionInjectedText = nil
            lastSessionFrontmostApp = nil
        }
        let result = DictationInjectionResult(requiresClipboardFallback: didFail || !didInject)
        let finishMessage = "dictation.finish didInject=\(didInject) didFail=\(didFail) "
            + "requiresClipboard=\(result.requiresClipboardFallback)"
        ShortcutDebugLogger.log(finishMessage)
        return result
    }

    private func flush(text: String) {
        let frontmost = frontmostAppProvider()
        lastFrontmostApp = frontmost
        if frontmost == bundleIdentifier {
            ShortcutDebugLogger.log("dictation.flush blocked frontmost=\(frontmost ?? "nil")")
            didFail = true
            return
        }

        let diff = DictationTextDiff.diff(from: lastInjected, to: text)
        let preview = String(diff.insertText.prefix(80)).replacingOccurrences(of: "\n", with: "\\n")
        let flushMessage = "dictation.flush frontmost=\(frontmost ?? "nil") "
            + "last=\(lastInjected.count) new=\(text.count) "
            + "backspace=\(diff.backspaceCount) insertLen=\(diff.insertText.count) "
            + "preview=\(preview)"
        ShortcutDebugLogger.log(flushMessage)
        var didSend = false
        if diff.backspaceCount > 0 {
            didSend = eventPoster.postBackspaces(diff.backspaceCount) || didSend
        }
        if !diff.insertText.isEmpty {
            didSend = eventPoster.postText(diff.insertText) || didSend
        } else if diff.backspaceCount > 0 {
            _ = eventPoster.postText("")
        }
        if !diff.insertText.isEmpty || diff.backspaceCount > 0 {
            lastInjected = text
            didInject = didInject || didSend
        }
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
