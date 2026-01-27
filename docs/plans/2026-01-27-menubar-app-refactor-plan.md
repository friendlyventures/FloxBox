# Menubar App Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Convert FloxBox to a menubar-only app with a menu-driven UX, separate Debug Panel and Settings windows, and a persistent Accessibility permissions window.

**Architecture:** The SwiftUI `App` owns a single `FloxBoxAppModel` that wires up `TranscriptionViewModel`, shortcut/permission coordinators, and window presenters. The main scene becomes a `MenuBarExtra` with a static status icon (recording state shown in the notch UI), plus explicit `Window` scenes for Debug Panel and Settings. Permissions are managed by a dedicated floating `NSWindow` shown automatically on launch when Accessibility is missing.

**Tech Stack:** SwiftUI, AppKit (`NSStatusItem` via `MenuBarExtra`, `NSWindow`), UserNotifications, existing FloxBoxCore view models/coordinators.

---

### Task 1: Extract Debug Panel + Settings Views

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Views/DebugPanelView.swift`
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Views/SettingsView.swift`
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Views/APIKeyRow.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Views/ContentView.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/ContentViewTests.swift`
- Create: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/DebugPanelViewTests.swift`
- Create: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/SettingsViewTests.swift`

**Step 1: Write the failing test**

```swift
// Packages/FloxBoxCore/Tests/FloxBoxCoreTests/DebugPanelViewTests.swift
import XCTest
import SwiftUI
@testable import FloxBoxCore

final class DebugPanelViewTests: XCTestCase {
    func testDebugPanelBuildsWithAPIKeyRow() {
        let model = FloxBoxAppModel.preview(configuration: .appStore)
        _ = DebugPanelView(model: model)
    }

    func testDebugPanelBuildsWithShortcutRecorder() {
        let model = FloxBoxAppModel.preview(configuration: .appStore)
        _ = DebugPanelView(model: model)
    }
}
```

```swift
// Packages/FloxBoxCore/Tests/FloxBoxCoreTests/SettingsViewTests.swift
import XCTest
import SwiftUI
@testable import FloxBoxCore

final class SettingsViewTests: XCTestCase {
    func testSettingsBuildsWithAPIKeyRow() {
        let model = FloxBoxAppModel.preview(configuration: .appStore)
        _ = SettingsView(model: model)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter DebugPanelViewTests`

Expected: FAIL with “Cannot find 'DebugPanelView' in scope”.

**Step 3: Write minimal implementation**

- Move the current `ContentView` layout into `DebugPanelView`.
- Extract `APIKeyRow` into `APIKeyRow.swift`.
- Create `SettingsView` that only renders the API key editor (reuse `APIKeyRow`).
- Keep `ContentView` as a thin wrapper (or delete and update all references).
- Add a simple `FloxBoxAppModel.preview` factory used by tests.

```swift
// Packages/FloxBoxCore/Sources/FloxBoxCore/Views/SettingsView.swift
import SwiftUI

public struct SettingsView: View {
    @Bindable var model: FloxBoxAppModel

    public init(model: FloxBoxAppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.title2.weight(.semibold))
            APIKeyRow(apiKey: $model.viewModel.apiKeyInput,
                      status: $model.viewModel.apiKeyStatus,
                      onSave: model.viewModel.saveAPIKey)
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 240)
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/FloxBoxCore --filter DebugPanelViewTests`

Expected: PASS.

Run: `swift test --package-path Packages/FloxBoxCore --filter SettingsViewTests`

Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Views \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests

git commit -m "refactor: split debug panel and settings views"
```

---

### Task 2: Introduce App Model to Own State/Coordinators

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/App/FloxBoxAppModel.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Views/DebugPanelView.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/PermissionsView.swift`
- Create: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/FloxBoxAppModelTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import FloxBoxCore

final class FloxBoxAppModelTests: XCTestCase {
    func testStartInvokesCoordinatorStarts() {
        let permissionsStarted = AtomicBool()
        let shortcutsStarted = AtomicBool()

        let model = FloxBoxAppModel(
            configuration: .appStore,
            makePermissionsCoordinator: { TestCoordinator(onStart: { permissionsStarted.value = true }) },
            makeShortcutCoordinator: { TestCoordinator(onStart: { shortcutsStarted.value = true }) }
        )

        model.start()

        XCTAssertTrue(permissionsStarted.value)
        XCTAssertTrue(shortcutsStarted.value)
    }
}

private final class TestCoordinator: Coordinating {
    private let onStart: () -> Void
    init(onStart: @escaping () -> Void) { self.onStart = onStart }
    func start() { onStart() }
    func stop() {}
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter FloxBoxAppModelTests`

Expected: FAIL with “Cannot find 'FloxBoxAppModel' in scope” and/or missing `Coordinating`.

**Step 3: Write minimal implementation**

- Add a lightweight `Coordinating` protocol in the app model file to allow test doubles.
- Implement `FloxBoxAppModel` to own:
  - `TranscriptionViewModel`
  - `ShortcutStore`
  - `PermissionsViewModel`
  - `PermissionsCoordinator` + `PermissionsWindowController`
  - `ShortcutCoordinator`
- Provide `start()` and `stop()` methods to start/stop coordinators.
- Provide `presentPermissions()` that calls coordinator `bringToFront()`.
- Add `static func preview(configuration:)` used by view tests.
- Update `DebugPanelView` to use the model’s view model and coordinators (remove `onAppear` start/stop).
- Update `PermissionsViewModel` or window messaging to emphasize Accessibility as required; notifications are optional.

```swift
@MainActor
public protocol Coordinating {
    func start()
    func stop()
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/FloxBoxCore --filter FloxBoxAppModelTests`

Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/App \
        Packages/FloxBoxCore/Sources/FloxBoxCore/Views/DebugPanelView.swift \
        Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/PermissionsView.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/FloxBoxAppModelTests.swift

git commit -m "feat: add app model for menubar lifecycle"
```

---

### Task 3: Menubar Menu + Window Scenes

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/App/MenubarMenu.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/App/FloxBoxAppRoot.swift`
- Modify: `FloxBox/FloxBoxApp.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/FloxBoxDistributionTests.swift`
- Create: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/MenubarMenuTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
import SwiftUI
@testable import FloxBoxCore

final class MenubarMenuTests: XCTestCase {
    func testMenuBuilds() {
        let model = FloxBoxAppModel.preview(configuration: .appStore)
        _ = MenubarMenu(model: model)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter MenubarMenuTests`

Expected: FAIL with “Cannot find 'MenubarMenu' in scope”.

**Step 3: Write minimal implementation**

- Add `MenubarMenu` view with menu items:
  - Open Debug Panel
  - Settings
  - Permissions (only shown when Accessibility missing)
  - Quit
- In `FloxBoxAppRoot.makeScene`, switch to a `MenuBarExtra` with `.menuBarExtraStyle(.menu)` and two `Window` scenes:
  - `Window("Debug Panel", id: "debug") { DebugPanelView(model: model) }`
  - `Window("Settings", id: "settings") { SettingsView(model: model) }`
- In `FloxBoxApp`, create a single `@StateObject` `FloxBoxAppModel` and pass into the root scene.

**Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/FloxBoxCore --filter MenubarMenuTests`

Expected: PASS.

**Step 5: Commit**

```bash
git add FloxBox/FloxBoxApp.swift \
        Packages/FloxBoxCore/Sources/FloxBoxCore/App \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/FloxBoxDistributionTests.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/MenubarMenuTests.swift

git commit -m "feat: add menubar menu and windows"
```

---

### Task 4: Permissions Flow (Accessibility Required)

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/App/FloxBoxAppModel.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/PermissionsView.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TranscriptionPermissionsTests.swift`

**Step 1: Write the failing test**

```swift
func testStartShowsPermissionsWindowWhenAccessibilityMissing() async {
    let presenter = PermissionsPresenterSpy()
    let model = TranscriptionViewModel(
        permissionsPresenter: { presenter.presented = true },
        accessibilityChecker: { false },
        secureInputChecker: { false }
    )

    await model.startAndWait()

    XCTAssertTrue(presenter.presented)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter TranscriptionPermissionsTests`

Expected: FAIL if the presenter is not called.

**Step 3: Write minimal implementation**

- Ensure `TranscriptionViewModel` always calls `permissionsPresenter()` when Accessibility is missing (already exists; keep behavior).
- In `FloxBoxAppModel.start()`, ensure the `PermissionsCoordinator` is started on app launch so the window auto-shows.
- Update `PermissionsView` copy to emphasize Accessibility is required; mark notifications as optional (non-blocking).

**Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/FloxBoxCore --filter TranscriptionPermissionsTests`

Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/App/FloxBoxAppModel.swift \
        Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/PermissionsView.swift \
        Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TranscriptionPermissionsTests.swift

git commit -m "feat: auto-present accessibility permissions"
```

---

### Task 5: Menubar-Only App (No Dock Icon)

**Files:**
- Modify: `FloxBox.xcodeproj/project.pbxproj`

**Step 1: Write the failing test**

Manual check only (Info.plist build setting). No unit test.

**Step 2: Apply change**

Add `INFOPLIST_KEY_LSUIElement = YES;` under each build configuration (Debug/Release for both app targets).

**Step 3: Manual verification**

Run the app from Xcode. Expected: no Dock icon, menu bar item visible.

**Step 4: Commit**

```bash
git add FloxBox.xcodeproj/project.pbxproj

git commit -m "chore: run as menubar-only app"
```

---

### Task 6: End-to-End Smoke Test

**Step 1: Build and run**

- Launch the app from Xcode.
- Verify menubar menu opens on left click.
- Open Debug Panel from menu.
- Open Settings from menu.
- If Accessibility missing, confirm Permissions window auto-opens.
- Hold push-to-talk: confirm notch recording UI shows recording state.
- Dictate into an external app and confirm insertion or clipboard fallback.
- Trigger a known error (secure input / missing permission) and confirm system notification appears.

**Step 2: Commit any small fixes**

```bash
git add <files>

git commit -m "fix: address menubar smoke test issues"
```

---

## Notes / Assumptions
- Recording state remains in the notch UI (no dynamic menubar icon state).
- Notifications are used for toasts; if notification permission is denied, app still works but with reduced feedback.
- Permissions window auto-dismisses once Accessibility is granted.
- Debug Panel may retain Start/Stop buttons for internal debugging; remove if you want strict PTT-only.

