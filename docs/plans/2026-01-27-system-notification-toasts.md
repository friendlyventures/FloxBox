# System Notification Toasts Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move all toast/error messaging out of the notch and into system notifications, while keeping the notch only for recording UI and renaming `VIndicator` to `RightIcon`.

**Architecture:** Introduce a `ToastPresenting` protocol with a `SystemNotificationPresenter` implementation based on `UNUserNotificationCenter`. Wire `TranscriptionViewModel` to use this presenter for all toasts/actions, and refactor the notch view/controller to only show recording UI. Extend the permissions window to request notification authorization alongside Accessibility.

**Tech Stack:** SwiftUI, AppKit, UserNotifications, XCTest

---

### Task 1: Add toast presenter protocol + test double, update view model tests

**Files:**
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TranscriptionPermissionsTests.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TestDoubles.swift`
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Notifications/ToastPresenting.swift`

**Step 1: Write the failing test**

Update `TranscriptionPermissionsTests` to assert toasts go through a new `TestToastPresenter` instead of the notch overlay:

```swift
@MainActor
func testStartBlockedWhenAccessibilityMissing() async {
    let overlay = TestNotchOverlay()
    let toast = TestToastPresenter()
    let injector = TestDictationInjector()
    let viewModel = TranscriptionViewModel(
        keychain: InMemoryKeychainStore(),
        audioCapture: TestAudioCapture(),
        realtimeFactory: { _ in TestRealtimeClient() },
        permissionRequester: { true },
        notchOverlay: overlay,
        toastPresenter: toast,
        accessibilityChecker: { false },
        secureInputChecker: { false },
        permissionsPresenter: {},
        dictationInjector: injector,
        clipboardWriter: { _ in }
    )
    viewModel.apiKeyInput = "sk-test"

    await viewModel.startAndWait()

    XCTAssertEqual(toast.toastMessages.last, "Accessibility permission required")
    XCTAssertEqual(injector.startCount, 0)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter TranscriptionPermissionsTests.testStartBlockedWhenAccessibilityMissing`
Expected: FAIL with “Extra argument 'toastPresenter'” or missing symbols.

**Step 3: Write minimal implementation**

Create `ToastPresenting` protocol and add `TestToastPresenter` in test doubles:

```swift
@MainActor
public protocol ToastPresenting: AnyObject {
    func showToast(_ message: String)
    func showAction(title: String, handler: @escaping () -> Void)
    func clearToast()
}
```

```swift
@MainActor
final class TestToastPresenter: ToastPresenting {
    private(set) var toastMessages: [String] = []
    private(set) var actionTitles: [String] = []

    func showToast(_ message: String) { toastMessages.append(message) }
    func showAction(title: String, handler _: @escaping () -> Void) { actionTitles.append(title) }
    func clearToast() {}
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/FloxBoxCore --filter TranscriptionPermissionsTests.testStartBlockedWhenAccessibilityMissing`
Expected: FAIL (view model not yet wired). This is expected until Task 2.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Notifications/ToastPresenting.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TestDoubles.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TranscriptionPermissionsTests.swift

git commit -m "test: add toast presenter test double and coverage"
```

---

### Task 2: Refactor notch UI + wire toast presenter into TranscriptionViewModel

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Notch/NotchRecordingView.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Notch/NotchRecordingController.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TestDoubles.swift`

**Step 1: Write the failing test**

Use the Task 1 test (still failing) as the failing test for this task.

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter TranscriptionPermissionsTests.testStartBlockedWhenAccessibilityMissing`
Expected: FAIL (no toast presenter in view model yet).

**Step 3: Write minimal implementation**

- Rename `VIndicator` → `RightIcon`.
- Remove `NotchToastView`, `NotchActionButton`, and toast state from `NotchRecordingState`.
- Update `NotchRecordingController` to remove toast methods and only handle `show()` / `hide()`.
- Update `NotchRecordingControlling` protocol to only include `show()` / `hide()`.
- Add `toastPresenter` dependency to `TranscriptionViewModel` with default `SystemNotificationPresenter()` (stub for now), and switch all `notchOverlay.showToast/showAction/clearToast` calls to `toastPresenter`.
- Update `TestNotchOverlay` to only track show/hide.

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/FloxBoxCore --filter TranscriptionPermissionsTests.testStartBlockedWhenAccessibilityMissing`
Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Notch/NotchRecordingView.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Notch/NotchRecordingController.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TestDoubles.swift

git commit -m "refactor: move toasts out of notch and rename indicator"
```

---

### Task 3: Implement system notification presenter and permission dialog updates

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Notifications/SystemNotificationPresenter.swift`
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/NotificationPermissionClient.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/PermissionsView.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/PermissionsCoordinator.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/PermissionsWindowController.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Views/ContentView.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/PermissionsCoordinatorTests.swift`

**Step 1: Write the failing test**

Add a new test to `PermissionsCoordinatorTests` that checks the window shows if either accessibility **or** notifications are missing:

```swift
@MainActor
func testCoordinatorShowsWindowWhenAnyPermissionMissing() async {
    let window = TestPermissionsWindow()
    let coordinator = PermissionsCoordinator(
        permissionChecker: { false },
        requestAccess: {},
        window: window
    )

    await coordinator.refresh()

    XCTAssertEqual(window.showCount, 1)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter PermissionsCoordinatorTests.testCoordinatorShowsWindowWhenAnyPermissionMissing`
Expected: FAIL with async mismatch or missing APIs.

**Step 3: Write minimal implementation**

- Implement `SystemNotificationPresenter` using `UNUserNotificationCenter`:
  - `showToast`: schedule immediate notification.
  - `showAction`: register a unique category/action and map action identifier → handler; invoke handler in delegate callback.
- Implement `NotificationPermissionClient` with:
  - `func fetchStatus() async -> NotificationAuthorizationStatus`
  - `func requestAuthorization() async -> NotificationAuthorizationStatus`
- Update `PermissionsViewModel`:
  - Track `notificationStatus` and computed `allGranted` (accessibility + notifications).
  - `refresh()` and `requestAccess()` become `async` and update both permissions.
- Update `PermissionsCoordinator` to use async `permissionChecker` and `requestAccess` closures.
- Update `PermissionsView` UI to include a notifications section (status + “Request Access” button).
- Update `PermissionsWindowController` size to accommodate the extra section.
- Update `ContentView` to pass new async closures and to construct `NotificationPermissionClient`.

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/FloxBoxCore --filter PermissionsCoordinatorTests.testCoordinatorShowsWindowWhenAnyPermissionMissing`
Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Notifications/SystemNotificationPresenter.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/NotificationPermissionClient.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/PermissionsView.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/PermissionsCoordinator.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/PermissionsWindowController.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Views/ContentView.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/PermissionsCoordinatorTests.swift

git commit -m "feat: add system notification toasts and notification permission"
```

---

### Task 4: Run targeted test suite

**Files:**
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TranscriptionPermissionsTests.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/PermissionsCoordinatorTests.swift`

**Step 1: Run focused tests**

Run:
```bash
swift test --package-path Packages/FloxBoxCore --filter TranscriptionPermissionsTests
swift test --package-path Packages/FloxBoxCore --filter PermissionsCoordinatorTests
```
Expected: PASS.

**Step 2: Commit (if any fixes)**

If any fixes were needed, commit them with a concise message.

---

## Notes
- Remove `NotchToastView` entirely; no toast text inside the notch.
- Use `UNUserNotificationCenter` for system‑level banners; no app window overlay.
- Retry action moves to notification action.

