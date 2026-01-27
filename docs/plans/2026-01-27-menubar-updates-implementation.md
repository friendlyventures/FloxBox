# Menubar Updates Action Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move “Check for Updates” to the menubar and remove the Updates section from the Debug panel.

**Architecture:** Add an optional update action to `FloxBoxDistributionConfiguration`, wire the Direct configuration to the updater controller, use the action in `MenubarMenu`, and remove the Debug panel Updates disclosure.

**Tech Stack:** Swift, SwiftUI.

---

### Task 1: Distribution config exposes update action

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Distribution/FloxBoxDistributionConfiguration.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCoreDirect/FloxBoxDirectServices.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/FloxBoxDistributionTests.swift`

**Step 1: Write the failing test**

```swift
@testable import FloxBoxCore
import XCTest

final class FloxBoxDistributionTests: XCTestCase {
    func testDirectConfigExposesCheckForUpdatesAction() {
        let config = FloxBoxDistributionConfiguration(label: "Direct", checkForUpdates: {})
        XCTAssertNotNil(config.checkForUpdates)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter FloxBoxDistributionTests/testDirectConfigExposesCheckForUpdatesAction`
Expected: FAIL (no checkForUpdates property).

**Step 3: Write minimal implementation**

- Add `public let checkForUpdates: (() -> Void)?` to `FloxBoxDistributionConfiguration`.
- Extend initializer to accept `checkForUpdates`.
- In `FloxBoxDirectServices.configuration()`, pass `checkForUpdates: { updaterController.checkForUpdates() }`.

**Step 4: Run test to verify it passes**

Run: `swift test --filter FloxBoxDistributionTests/testDirectConfigExposesCheckForUpdatesAction`
Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Distribution/FloxBoxDistributionConfiguration.swift \
        Packages/FloxBoxCore/Sources/FloxBoxCoreDirect/FloxBoxDirectServices.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/FloxBoxDistributionTests.swift

git commit -m "feat: add updates action to distribution config"
```

---

### Task 2: Menubar “Check for Updates” + remove debug Updates section

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/App/MenubarMenu.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Views/DebugPanelView.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/MenubarMenuTests.swift`

**Step 1: Write the failing test**

```swift
@MainActor
func testMenuBuildsWithUpdatesAction() {
    let config = FloxBoxDistributionConfiguration(label: "Direct", checkForUpdates: {})
    let model = FloxBoxAppModel.preview(configuration: config)
    _ = MenubarMenu(model: model)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter MenubarMenuTests/testMenuBuildsWithUpdatesAction`
Expected: FAIL (no action wired).

**Step 3: Write minimal implementation**

- In `MenubarMenu`, add a “Check for Updates” button when `model.configuration.checkForUpdates` is not nil.
- In `DebugPanelView`, remove the Updates disclosure group.

**Step 4: Run test to verify it passes**

Run: `swift test --filter MenubarMenuTests/testMenuBuildsWithUpdatesAction`
Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/App/MenubarMenu.swift \
        Packages/FloxBoxCore/Sources/FloxBoxCore/Views/DebugPanelView.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/MenubarMenuTests.swift

git commit -m "feat: move updates action to menubar"
```

---

### Task 3: Full test pass

**Step 1: Run full test suite**

Run: `swift test` (from `Packages/FloxBoxCore`)
Expected: PASS

**Step 2: Commit (if needed)**

```bash
git add -A
git commit -m "chore: finalize menubar updates"
```

---

Plan complete and saved to `docs/plans/2026-01-27-menubar-updates-implementation.md`. Two execution options:

1. Subagent-Driven (this session)
2. Parallel Session (separate)

Which approach?
