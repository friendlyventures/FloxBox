# Peek-and-Space Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a conservative “peek-and-space” heuristic that prepends a single space when inserting dictation into external fields if the caret is after a non-whitespace character and the dictated text doesn’t start with whitespace or punctuation.

**Architecture:** Introduce a focused text context provider (AX-backed in production, stubbed in tests) to fetch the focused field value and caret index. Dictation injection resolves a session prefix once (on first apply) and injects `prefix + text` for diffing, so the prefix is inserted only once.

**Tech Stack:** Swift (AppKit/ApplicationServices), Accessibility API (AXUIElement), Swift Package tests (XCTest).

> **Note:** Full test suite currently crashes in `ContentViewTests` due to `SystemNotificationPresenter` when run via `swift test`. Run targeted tests for this feature.

---

### Task 1: Add spacing tests and stub provider

**Files:**
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/DictationInjectionControllerTests.swift`

**Step 1: Write failing tests for spacing behavior**

Add tests that assume a new focused text context provider exists:

```swift
func testAddsLeadingSpaceWhenPrecedingCharIsNonWhitespace() {
    let poster = TestEventPoster()
    let coalescer = ImmediateCoalescer()
    let provider = TestFocusedTextContextProvider(value: "foo bar", caretIndex: 7)
    let injector = DictationInjectionController(
        eventPoster: poster,
        coalescer: coalescer,
        focusedTextContextProvider: provider,
        frontmostAppProvider: { "com.apple.TextEdit" },
        bundleIdentifier: "com.floxbox.app"
    )

    injector.startSession()
    injector.apply(text: "baz")

    XCTAssertEqual(poster.inserted, [" baz"])
}

func testDoesNotAddLeadingSpaceWhenDictationStartsWithPunctuation() {
    let poster = TestEventPoster()
    let coalescer = ImmediateCoalescer()
    let provider = TestFocusedTextContextProvider(value: "foo", caretIndex: 3)
    let injector = DictationInjectionController(
        eventPoster: poster,
        coalescer: coalescer,
        focusedTextContextProvider: provider,
        frontmostAppProvider: { "com.apple.TextEdit" },
        bundleIdentifier: "com.floxbox.app"
    )

    injector.startSession()
    injector.apply(text: ",")

    XCTAssertEqual(poster.inserted, [","])
}
```

Also add a test to ensure prefix is inserted once across partial updates:

```swift
func testPrefixInsertedOnceAcrossUpdates() {
    let poster = TestEventPoster()
    let coalescer = ImmediateCoalescer()
    let provider = TestFocusedTextContextProvider(value: "foo", caretIndex: 3)
    let injector = DictationInjectionController(
        eventPoster: poster,
        coalescer: coalescer,
        focusedTextContextProvider: provider,
        frontmostAppProvider: { "com.apple.TextEdit" },
        bundleIdentifier: "com.floxbox.app"
    )

    injector.startSession()
    injector.apply(text: "hello")
    injector.apply(text: "hello world")

    XCTAssertEqual(poster.inserted, [" hello", " world"])
}
```

Add a test stub inside the file:

```swift
private struct TestFocusedTextContextProvider: FocusedTextContextProviding {
    let value: String
    let caretIndex: Int
    func focusedTextContext() -> FocusedTextContext? {
        .init(value: value, caretIndex: caretIndex)
    }
}
```

**Step 2: Run tests to confirm failure**

Run: `swift test --package-path Packages/FloxBoxCore --filter DictationInjectionControllerTests`

Expected: FAIL because `FocusedTextContextProviding` / new initializer doesn’t exist yet.

**Step 3: Commit test changes**

```bash
git add Packages/FloxBoxCore/Tests/FloxBoxCoreTests/DictationInjectionControllerTests.swift
git commit -m "test: cover peek-and-space heuristic"
```

---

### Task 2: Implement spacing logic in the injection controller

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Dictation/FocusedTextContextProvider.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Dictation/DictationInjectionController.swift`

**Step 1: Add context provider protocol + model**

Create the model and protocol in the new file:

```swift
import ApplicationServices

public struct FocusedTextContext: Equatable {
    public let value: String
    public let caretIndex: Int
}

public protocol FocusedTextContextProviding {
    func focusedTextContext() -> FocusedTextContext?
}
```

**Step 2: Add session prefix logic (minimal implementation)**

Modify `DictationInjectionController`:
- Add dependency: `focusedTextContextProvider: FocusedTextContextProviding` with default.
- Add `private var sessionPrefix: String?`.
- In `startSession()`, reset `sessionPrefix = nil`.
- In `apply(text:)`, resolve prefix once and inject `prefix + text`.

Minimal helper:

```swift
private func resolvedText(for text: String) -> String {
    if sessionPrefix == nil {
        sessionPrefix = determinePrefix(for: text)
    }
    return (sessionPrefix ?? "") + text
}
```

`determinePrefix(for:)` should:
- return `""` if `text` is empty.
- return `""` if `text` starts with whitespace or punctuation.
- return `""` if no focused context is available, caret is 0, caret is out of range, or preceding char is whitespace.
- otherwise return `" "`.

Use `NSString` to check the preceding character using the caret index (AX uses UTF-16 indexes).

**Step 3: Run tests**

Run: `swift test --package-path Packages/FloxBoxCore --filter DictationInjectionControllerTests`

Expected: PASS.

**Step 4: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Dictation/FocusedTextContextProvider.swift \
        Packages/FloxBoxCore/Sources/FloxBoxCore/Dictation/DictationInjectionController.swift
git commit -m "feat: add dictation prefix heuristic"
```

---

### Task 3: Add AX-backed provider (safe/early exit behavior)

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Dictation/FocusedTextContextProvider.swift`
- Create: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/FocusedTextContextProviderTests.swift`

**Step 1: Write failing test**

```swift
func testProviderReturnsNilWhenNotTrusted() {
    let provider = AXFocusedTextContextProvider(isTrusted: { false })
    XCTAssertNil(provider.focusedTextContext())
}
```

**Step 2: Run test to confirm failure**

Run: `swift test --package-path Packages/FloxBoxCore --filter FocusedTextContextProviderTests`

Expected: FAIL (provider not implemented).

**Step 3: Implement AX provider**

Add to `FocusedTextContextProvider.swift`:

```swift
public struct AXFocusedTextContextProvider: FocusedTextContextProviding {
    private let systemElement: AXUIElement
    private let isTrusted: () -> Bool

    public init(
        systemElement: AXUIElement = AXUIElementCreateSystemWide(),
        isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }
    ) {
        self.systemElement = systemElement
        self.isTrusted = isTrusted
    }

    public func focusedTextContext() -> FocusedTextContext? {
        guard isTrusted() else { return nil }
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return nil }

        if isSecureTextElement(element) {
            return nil
        }

        guard let value = copyString(element, attribute: kAXValueAttribute) else { return nil }
        guard let range = copyRange(element, attribute: kAXSelectedTextRangeAttribute) else { return nil }
        guard range.location >= 0 else { return nil }

        let nsValue = value as NSString
        guard range.location <= nsValue.length else { return nil }

        return FocusedTextContext(value: value, caretIndex: range.location)
    }

    private func copyString(_ element: AXUIElement, attribute: CFString) -> String? { ... }
    private func copyRange(_ element: AXUIElement, attribute: CFString) -> CFRange? { ... }
    private func isSecureTextElement(_ element: AXUIElement) -> Bool { ... }
}
```

`isSecureTextElement` should check `kAXSubroleAttribute == kAXSecureTextFieldSubrole` (fallback to string contains “Secure” if needed).

**Step 4: Run tests**

Run: `swift test --package-path Packages/FloxBoxCore --filter FocusedTextContextProviderTests`

Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Dictation/FocusedTextContextProvider.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/FocusedTextContextProviderTests.swift
git commit -m "feat: add AX focused text context provider"
```

---

### Task 4: Wire AX provider as default + run targeted tests

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Dictation/DictationInjectionController.swift`

**Step 1: Set default provider**

Set `focusedTextContextProvider: FocusedTextContextProviding = AXFocusedTextContextProvider()` in init.

**Step 2: Run targeted tests**

Run:
- `swift test --package-path Packages/FloxBoxCore --filter DictationInjectionControllerTests`
- `swift test --package-path Packages/FloxBoxCore --filter FocusedTextContextProviderTests`

Expected: PASS.

**Step 3: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Dictation/DictationInjectionController.swift
git commit -m "chore: default to AX focused text context"
```

---

### Task 5: Verify behavior manually

**Step 1: Build and run app**
- Use your normal run flow.

**Step 2: Manual check**
- In an external text field with existing text (caret at end), dictate “baz” and ensure a single leading space is inserted.
- Dictate a punctuation-only utterance (e.g., “comma”) and confirm no leading space is inserted.

**Step 3: Note any failures**
- If AX data unavailable, ensure behavior matches current baseline (no prefix).

---

## Execution Handoff
Plan complete and saved to `docs/plans/2026-01-27-dictation-peek-space-implementation.md`.

Two execution options:
1) **Subagent-Driven (this session)** – I dispatch a fresh subagent per task, review between tasks.
2) **Parallel Session (separate)** – Open a new session with `superpowers:executing-plans` and run tasks sequentially.

Which approach?
