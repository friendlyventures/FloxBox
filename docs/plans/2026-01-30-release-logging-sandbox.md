# Release Logging + Sandbox Warning Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable always-on direct-release dictation logging and eliminate the sandbox build-setting warning.

**Architecture:** Add injectable logging to the clipboard insertion path so we can capture paste/restore timing in release builds, then enable logging compilation for direct distribution builds. Update the direct target build settings to match non-sandbox entitlements.

**Tech Stack:** Swift (FloxBoxCore), Xcode build settings, XCTest.

### Task 1: Add testable clipboard-insertion logging

**Files:**
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/ClipboardTextInserterTests.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Dictation/ClipboardTextInserter.swift`

**Step 1: Write the failing test**

```swift
func testInsertLogsPasteAndRestoreWhenPasteFails() {
    let pasteboard = FakePasteboard(items: [])
    var logs: [String] = []
    let inserter = ClipboardTextInserter(
        pasteboardProvider: { pasteboard },
        commandVPaster: AlwaysFailCommandVPaster(),
        restoreDelay: 0,
        restoreScheduler: { _, work in work() },
        logger: { logs.append($0) }
    )

    _ = inserter.insert(text: "Hello")

    XCTAssertTrue(logs.contains { $0.contains("clipboard.insert.start") })
    XCTAssertTrue(logs.contains { $0.contains("clipboard.insert.commandV result=false") })
    XCTAssertTrue(logs.contains { $0.contains("clipboard.restore.immediate") })
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter ClipboardTextInserterTests/testInsertLogsPasteAndRestoreWhenPasteFails`
Expected: FAIL because `ClipboardTextInserter` does not accept `logger` and no log lines exist.

**Step 3: Write minimal implementation**

```swift
public final class ClipboardTextInserter: DictationTextInserting {
    private let logger: (String) -> Void

    public init(..., logger: @escaping (String) -> Void = ShortcutDebugLogger.log) {
        self.logger = logger
        ...
    }

    public func insert(text: String) -> Bool {
        logger("clipboard.insert.start len=\(text.count) delay=\(restoreDelay)")
        ...
        logger("clipboard.insert.commandV result=\(posted)")
        ...
        logger("clipboard.restore.immediate")
        ...
        logger("clipboard.restore.deferred")
        ...
        logger("clipboard.restore.skip changeCount=\(pasteboard.changeCount)")
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/FloxBoxCore --filter ClipboardTextInserterTests/testInsertLogsPasteAndRestoreWhenPasteFails`
Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Dictation/ClipboardTextInserter.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/ClipboardTextInserterTests.swift
git commit -m "test: add clipboard logging coverage"
```

### Task 2: Enable logging in direct distribution builds

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/ShortcutDebugLogger.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Support/DebugLog.swift`

**Step 1: Update compile guards**

```swift
#if DEBUG || DIRECT_DISTRIBUTION
```

**Step 2: Sanity build (no tests required for config-only change)**

Run: `swift test --package-path Packages/FloxBoxCore --filter ClipboardTextInserterTests/testInsertLogsPasteAndRestoreWhenPasteFails`
Expected: PASS.

**Step 3: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/ShortcutDebugLogger.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Support/DebugLog.swift
git commit -m "chore: enable direct-distribution logging"
```

### Task 3: Fix sandbox build setting mismatch (direct target)

**Files:**
- Modify: `FloxBox.xcodeproj/project.pbxproj`

**Step 1: Set ENABLE_APP_SANDBOX = NO for FloxBox target (Debug + Release)**

Update the `FloxBox` target build settings to match `FloxBox/FloxBox.entitlements`.

**Step 2: Verify build settings (config-only)**

Run: `xcodebuild -showBuildSettings -target FloxBox -configuration Release | rg ENABLE_APP_SANDBOX`
Expected: `ENABLE_APP_SANDBOX = NO`

**Step 3: Commit**

```bash
git add FloxBox.xcodeproj/project.pbxproj
git commit -m "chore: disable sandbox setting for direct build"
```

