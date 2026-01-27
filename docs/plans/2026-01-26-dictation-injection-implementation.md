# Follow-Focus Dictation Injection Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Stream realtime transcription into the currently focused text field via key event injection, with Accessibility-only gating, a persistent permissions window, and a clipboard fallback when insertion fails.

**Architecture:** Add a dictation injection subsystem (diff + coalescer + event poster) in FloxBoxCore and wire it into `TranscriptionViewModel` for start/stop + live updates. Add an Accessibility permissions coordinator + always-on-top window in the app to guide users. Remove the in-app transcript view so dictation goes to external apps only.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, CoreGraphics/Carbon, Swift Package Manager, macOS 14.6.

**Skills:** Follow @superpowers:test-driven-development for testable units and @superpowers:systematic-debugging if any test fails.

### Task 1: Add dictation text diff utility

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Dictation/DictationTextDiff.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/DictationTextDiffTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import FloxBoxCore

final class DictationTextDiffTests: XCTestCase {
    func testInsertFromEmpty() {
        let diff = DictationTextDiff.diff(from: "", to: "hello")
        XCTAssertEqual(diff.backspaceCount, 0)
        XCTAssertEqual(diff.insertText, "hello")
    }

    func testDeleteSuffix() {
        let diff = DictationTextDiff.diff(from: "hello", to: "hel")
        XCTAssertEqual(diff.backspaceCount, 2)
        XCTAssertEqual(diff.insertText, "")
    }

    func testReplaceTail() {
        let diff = DictationTextDiff.diff(from: "hello world", to: "hello there")
        XCTAssertEqual(diff.backspaceCount, 5)
        XCTAssertEqual(diff.insertText, "there")
    }

    func testNoChange() {
        let diff = DictationTextDiff.diff(from: "same", to: "same")
        XCTAssertEqual(diff.backspaceCount, 0)
        XCTAssertEqual(diff.insertText, "")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter DictationTextDiffTests`
Expected: FAIL with “cannot find type ‘DictationTextDiff’ in scope”.

**Step 3: Write minimal implementation**

`Packages/FloxBoxCore/Sources/FloxBoxCore/Dictation/DictationTextDiff.swift`:

```swift
import Foundation

public struct DictationTextDiff: Equatable {
    public let backspaceCount: Int
    public let insertText: String

    public static func diff(from oldValue: String, to newValue: String) -> DictationTextDiff {
        let prefixCount = zip(oldValue, newValue)
            .prefix { $0 == $1 }
            .count
        let deleteCount = max(0, oldValue.count - prefixCount)
        let insert = String(newValue.dropFirst(prefixCount))
        return DictationTextDiff(backspaceCount: deleteCount, insertText: insert)
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/FloxBoxCore --filter DictationTextDiffTests`
Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Dictation/DictationTextDiff.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/DictationTextDiffTests.swift
git commit -m "feat: add dictation text diff utility"
```

---

### Task 2: Add update coalescer for injection

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Dictation/DictationUpdateCoalescer.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/DictationUpdateCoalescerTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import FloxBoxCore

final class DictationUpdateCoalescerTests: XCTestCase {
    func testCoalescerEmitsLatestValueOnFire() {
        let timer = TestCoalescerTimer()
        let coalescer = DictationUpdateCoalescer(interval: 0.1, timerFactory: { _, handler in
            timer.handler = handler
            return timer
        })

        var flushed: [String] = []
        coalescer.enqueue("first") { flushed.append($0) }
        coalescer.enqueue("second") { flushed.append($0) }

        timer.fire()
        XCTAssertEqual(flushed, ["second"])
    }
}

private final class TestCoalescerTimer: CoalescerTimer {
    var handler: (() -> Void)?
    func invalidate() {}
    func fire() { handler?() }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter DictationUpdateCoalescerTests`
Expected: FAIL with missing types.

**Step 3: Write minimal implementation**

`Packages/FloxBoxCore/Sources/FloxBoxCore/Dictation/DictationUpdateCoalescer.swift`:

```swift
import Foundation

public protocol CoalescerTimer {
    func invalidate()
}

public final class DictationUpdateCoalescer {
    public typealias TimerFactory = (TimeInterval, @escaping () -> Void) -> CoalescerTimer

    private let interval: TimeInterval
    private let timerFactory: TimerFactory
    private var timer: CoalescerTimer?
    private var pendingText: String?

    public init(interval: TimeInterval, timerFactory: @escaping TimerFactory = DictationUpdateCoalescer.defaultTimerFactory) {
        self.interval = interval
        self.timerFactory = timerFactory
    }

    public func enqueue(_ text: String, flush: @escaping (String) -> Void) {
        pendingText = text
        guard timer == nil else { return }
        timer = timerFactory(interval) { [weak self] in
            guard let self, let pending = self.pendingText else { return }
            self.pendingText = nil
            self.timer?.invalidate()
            self.timer = nil
            flush(pending)
        }
    }

    public func cancel() {
        timer?.invalidate()
        timer = nil
        pendingText = nil
    }

    private static func defaultTimerFactory(interval: TimeInterval, handler: @escaping () -> Void) -> CoalescerTimer {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            handler()
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/FloxBoxCore --filter DictationUpdateCoalescerTests`
Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Dictation/DictationUpdateCoalescer.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/DictationUpdateCoalescerTests.swift
git commit -m "feat: add dictation update coalescer"
```

---

### Task 3: Add dictation injection controller + event poster

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Dictation/DictationInjectionController.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/DictationInjectionControllerTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import FloxBoxCore

final class DictationInjectionControllerTests: XCTestCase {
    func testApplyTextPostsBackspacesAndInsert() {
        let poster = TestEventPoster()
        let coalescer = ImmediateCoalescer()
        let injector = DictationInjectionController(
            eventPoster: poster,
            coalescer: coalescer,
            frontmostAppProvider: { "com.apple.TextEdit" },
            bundleIdentifier: "com.floxbox.app"
        )

        injector.startSession()
        injector.apply(text: "hello")
        injector.apply(text: "hel")

        XCTAssertEqual(poster.backspaceCount, 2)
        XCTAssertEqual(poster.inserted, ["hello", ""])
    }

    func testFrontmostIsFloxBoxMarksFailure() {
        let poster = TestEventPoster()
        let coalescer = ImmediateCoalescer()
        let injector = DictationInjectionController(
            eventPoster: poster,
            coalescer: coalescer,
            frontmostAppProvider: { "com.floxbox.app" },
            bundleIdentifier: "com.floxbox.app"
        )

        injector.startSession()
        injector.apply(text: "hello")
        let result = injector.finishSession()

        XCTAssertTrue(result.requiresClipboardFallback)
        XCTAssertEqual(poster.inserted, [])
    }
}

private final class TestEventPoster: DictationEventPosting {
    var backspaceCount = 0
    var inserted: [String] = []

    func postBackspaces(_ count: Int) -> Bool {
        backspaceCount += count
        return true
    }

    func postText(_ text: String) -> Bool {
        inserted.append(text)
        return true
    }
}

private final class ImmediateCoalescer: DictationUpdateCoalescing {
    func enqueue(_ text: String, flush: @escaping (String) -> Void) { flush(text) }
    func cancel() {}
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter DictationInjectionControllerTests`
Expected: FAIL with missing types.

**Step 3: Write minimal implementation**

`Packages/FloxBoxCore/Sources/FloxBoxCore/Dictation/DictationInjectionController.swift`:

```swift
import AppKit
import Carbon
import CoreGraphics

public protocol DictationUpdateCoalescing {
    func enqueue(_ text: String, flush: @escaping (String) -> Void)
    func cancel()
}

public protocol DictationEventPosting {
    func postBackspaces(_ count: Int) -> Bool
    func postText(_ text: String) -> Bool
}

public struct DictationInjectionResult: Equatable {
    public let requiresClipboardFallback: Bool
}

@MainActor
public final class DictationInjectionController {
    private let eventPoster: DictationEventPosting
    private let coalescer: DictationUpdateCoalescing
    private let frontmostAppProvider: () -> String?
    private let bundleIdentifier: String

    private var lastInjected = ""
    private var didInject = false
    private var didFail = false

    public init(
        eventPoster: DictationEventPosting = CGEventPoster(),
        coalescer: DictationUpdateCoalescing = DictationUpdateCoalescer(interval: 0.08),
        frontmostAppProvider: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? ""
    ) {
        self.eventPoster = eventPoster
        self.coalescer = coalescer
        self.frontmostAppProvider = frontmostAppProvider
        self.bundleIdentifier = bundleIdentifier
    }

    public func startSession() {
        lastInjected = ""
        didInject = false
        didFail = false
        coalescer.cancel()
    }

    public func apply(text: String) {
        coalescer.enqueue(text) { [weak self] in
            self?.flush(text: $0)
        }
    }

    public func finishSession() -> DictationInjectionResult {
        coalescer.cancel()
        return DictationInjectionResult(requiresClipboardFallback: didFail || !didInject)
    }

    private func flush(text: String) {
        guard frontmostAppProvider() != bundleIdentifier else {
            didFail = true
            return
        }

        let diff = DictationTextDiff.diff(from: lastInjected, to: text)
        if diff.backspaceCount > 0 {
            didInject = didInject || eventPoster.postBackspaces(diff.backspaceCount)
        }
        if !diff.insertText.isEmpty {
            didInject = didInject || eventPoster.postText(diff.insertText)
        }
        if !diff.insertText.isEmpty || diff.backspaceCount > 0 {
            lastInjected = text
        }
    }
}

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
```

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/FloxBoxCore --filter DictationInjectionControllerTests`
Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Dictation/DictationInjectionController.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/DictationInjectionControllerTests.swift
git commit -m "feat: add dictation injection controller"
```

---

### Task 4: Add Accessibility permission coordinator + window

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/AccessibilityPermissionClient.swift`
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/PermissionsWindowController.swift`
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/PermissionsView.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/PermissionsCoordinatorTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import FloxBoxCore

final class PermissionsCoordinatorTests: XCTestCase {
    @MainActor
    func testCoordinatorShowsWindowWhenMissing() {
        let window = TestPermissionsWindow()
        let coordinator = PermissionsCoordinator(
            permissionChecker: { false },
            requestAccess: {},
            window: window
        )

        coordinator.refresh()

        XCTAssertEqual(window.showCount, 1)
    }
}

@MainActor
private final class TestPermissionsWindow: PermissionsWindowPresenting {
    var showCount = 0
    func show() { showCount += 1 }
    func hide() {}
    func bringToFront() {}
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter PermissionsCoordinatorTests`
Expected: FAIL with missing types.

**Step 3: Write minimal implementation**

`Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/AccessibilityPermissionClient.swift`:

```swift
import ApplicationServices

public struct AccessibilityPermissionClient {
    public var isTrusted: () -> Bool
    public var requestAccess: () -> Void

    public init(
        isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        requestAccess: @escaping () -> Void = {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    ) {
        self.isTrusted = isTrusted
        self.requestAccess = requestAccess
    }
}
```

`Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/PermissionsWindowController.swift`:

```swift
import AppKit
import SwiftUI

@MainActor
public protocol PermissionsWindowPresenting {
    func show()
    func hide()
    func bringToFront()
}

@MainActor
public final class PermissionsWindowController: PermissionsWindowPresenting {
    private var window: NSWindow?
    private let viewModel: PermissionsViewModel

    public init(viewModel: PermissionsViewModel) {
        self.viewModel = viewModel
    }

    public func show() {
        ensureWindow()
        window?.orderFrontRegardless()
    }

    public func hide() {
        window?.orderOut(nil)
    }

    public func bringToFront() {
        ensureWindow()
        NSApp.activate(ignoringOtherApps: true)
        window?.orderFrontRegardless()
    }

    private func ensureWindow() {
        guard window == nil else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()
        window.title = "Permissions Required"
        window.contentView = NSHostingView(rootView: PermissionsView(viewModel: viewModel))
        self.window = window
    }
}
```

`Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/PermissionsView.swift`:

```swift
import SwiftUI

@MainActor
public final class PermissionsViewModel: ObservableObject {
    @Published public var isTrusted: Bool
    private let permissionClient: AccessibilityPermissionClient

    public init(permissionClient: AccessibilityPermissionClient) {
        self.permissionClient = permissionClient
        self.isTrusted = permissionClient.isTrusted()
    }

    public func refresh() {
        isTrusted = permissionClient.isTrusted()
    }

    public func requestAccess() {
        permissionClient.requestAccess()
        refresh()
    }
}

public struct PermissionsView: View {
    @ObservedObject var viewModel: PermissionsViewModel

    public init(viewModel: PermissionsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Allow Accessibility")
                .font(.headline)
            Text("FloxBox needs Accessibility access to type into other apps.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Request Access") {
                    viewModel.requestAccess()
                }
                if viewModel.isTrusted {
                    Text("Granted").foregroundStyle(.green)
                } else {
                    Text("Missing").foregroundStyle(.red)
                }
            }
            Spacer()
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 220)
    }
}
```

`Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/PermissionsCoordinator.swift` (add in same folder):

```swift
import Foundation

@MainActor
public final class PermissionsCoordinator {
    private let permissionChecker: () -> Bool
    private let requestAccess: () -> Void
    private let window: PermissionsWindowPresenting
    private var timer: Timer?

    public init(
        permissionChecker: @escaping () -> Bool,
        requestAccess: @escaping () -> Void,
        window: PermissionsWindowPresenting
    ) {
        self.permissionChecker = permissionChecker
        self.requestAccess = requestAccess
        self.window = window
    }

    public func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    public func refresh() {
        if permissionChecker() {
            window.hide()
        } else {
            window.show()
        }
    }

    public func bringToFront() {
        window.bringToFront()
    }

    public func request() {
        requestAccess()
        refresh()
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/FloxBoxCore --filter PermissionsCoordinatorTests`
Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/PermissionsCoordinatorTests.swift
git commit -m "feat: add accessibility permissions window"
```

---

### Task 5: Gate recording + inject dictation + clipboard fallback

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TestDoubles.swift`
- Create: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TranscriptionPermissionsTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import FloxBoxCore

@MainActor
final class TranscriptionPermissionsTests: XCTestCase {
    func testStartBlockedWhenAccessibilityMissing() async {
        let overlay = TestNotchOverlay()
        let injector = TestDictationInjector()
        let viewModel = TranscriptionViewModel(
            keychain: InMemoryKeychainStore(),
            audioCapture: TestAudioCapture(),
            realtimeFactory: { _ in TestRealtimeClient() },
            permissionRequester: { true },
            notchOverlay: overlay,
            accessibilityChecker: { false },
            secureInputChecker: { false },
            permissionsPresenter: { },
            dictationInjector: injector,
            clipboardWriter: { _ in }
        )

        await viewModel.startAndWait()

        XCTAssertEqual(overlay.toastMessages.last, "Accessibility permission required")
        XCTAssertEqual(injector.startCount, 0)
    }
}

@MainActor
private final class TestDictationInjector: DictationInjectionControlling {
    var startCount = 0
    func startSession() { startCount += 1 }
    func apply(text: String) {}
    func finishSession() -> DictationInjectionResult { .init(requiresClipboardFallback: false) }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter TranscriptionPermissionsTests`
Expected: FAIL with missing init parameters/types.

**Step 3: Write minimal implementation**

Update `TranscriptionViewModel` to accept new injected dependencies:

- `accessibilityChecker: () -> Bool` (default uses `AccessibilityPermissionClient().isTrusted()`)
- `secureInputChecker: () -> Bool` (default uses `IsSecureEventInputEnabled()`)
- `permissionsPresenter: () -> Void` (default no-op)
- `dictationInjector: DictationInjectionControlling` (default `DictationInjectionController()`)
- `clipboardWriter: (String) -> Void` (default uses `NSPasteboard.general`)

Then, in `startInternal()`:
- Check accessibility first; if missing, show toast + bring permissions window and return.
- Check secure input; if enabled, show toast and return.
- After starting recording, call `dictationInjector.startSession()`.

In `handle(_:)` and `applyRestTranscription(_:)`:
- After updating `transcriptStore`, call `dictationInjector.apply(text: transcriptStore.displayText)`.

In `stopInternal()`:
- Call `let result = dictationInjector.finishSession()`; if `result.requiresClipboardFallback` then copy full text to clipboard and show toast "Couldn't insert text. Paste with Cmd+V.".

Update `TestDoubles.swift` with stubs for the new dependencies.

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/FloxBoxCore --filter TranscriptionPermissionsTests`
Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TestDoubles.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TranscriptionPermissionsTests.swift
git commit -m "feat: gate recording and inject dictation"
```

---

### Task 6: Remove transcript UI + wire permissions window

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Views/ContentView.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/App/FloxBoxAppRoot.swift` (if needed for window lifecycle)

**Step 1: Write the failing test**

_No new tests required (UI refactor). Proceed with a minimal change set._

**Step 2: Update the UI and permissions wiring**

- Remove the right-side transcript `TextEditor` panel.
- Move the “Transcription Prompt” `TextEditor` into the left column as a `sectionCard`.
- Add a small note card like “Dictation goes to your active app.” (optional but helpful).
- Instantiate the permissions view model + window controller + coordinator in `ContentView` and start it on `onAppear`.
- Pass a `permissionsPresenter` closure into the `TranscriptionViewModel` that calls `permissionsCoordinator.bringToFront()`.

**Step 3: Manual QA**

- Launch with Accessibility disabled → permissions window appears and stays floating.
- Click “Request Access” → system prompt appears, then window auto-dismisses when granted.
- Record with missing permission → toast appears and permissions window is brought forward.

**Step 4: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Views/ContentView.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/App/FloxBoxAppRoot.swift

git commit -m "feat: remove transcript view and add permissions window"
```

---

### Task 7: Full test run

**Step 1: Run full test suite**

Run: `swift test --package-path Packages/FloxBoxCore`
Expected: PASS (integration test may be skipped without env var).

**Step 2: Commit (if changes from previous steps)**

```bash
git status --short
```

If anything remains uncommitted, stage and commit with a short message describing the fix.

---

## Notes / Behaviors

- **Accessibility only** is required for now. Additional permissions can be added later via the same coordinator.
- The permissions window is **closable** but reappears on record attempts if missing.
- Injection follows focus; no attempt to lock a target app.
- Clipboard fallback is used when injection fails or never injected during a session.

