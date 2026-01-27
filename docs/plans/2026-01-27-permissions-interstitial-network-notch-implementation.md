# Permissions Interstitial + Network Notch Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add explicit permissions interstitial (Input Monitoring, Accessibility, Microphone) with per-button requests that open System Settings, and add notch network-loading/cancel behavior with strict timeouts and retries.

**Architecture:** Introduce permission clients + settings opener into `PermissionsViewModel`, update the interstitial UI and presentation logic, stop auto-requesting Input Monitoring from the event tap backend, extend the notch overlay to show a delayed spinner/cancel affordance, and update `TranscriptionViewModel` to track an awaiting-network state, enforce timeouts, and handle cancel/final-failure notification.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, CoreGraphics, AVFoundation, URLSession.

---

### Task 1: Add permission clients + view model state

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/InputMonitoringPermissionClient.swift`
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/MicrophonePermissionClient.swift`
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/SystemSettingsOpener.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/PermissionsView.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Permissions/PermissionsViewModelTests.swift`

**Step 1: Write the failing tests**

```swift
@MainActor
func testAllRequiredGrantedRequiresInputMonitoringAccessibilityMicrophone() async {
    let input = InputMonitoringPermissionClient(
        isGranted: { true },
        requestAccess: { true },
    )
    let accessibility = AccessibilityPermissionClient(
        isTrusted: { true },
        requestAccess: {},
    )
    let microphone = MicrophonePermissionClient(
        authorizationStatus: { .authorized },
        requestAccess: { true },
    )
    let opener = SystemSettingsOpener(open: {})

    let viewModel = PermissionsViewModel(
        inputMonitoringClient: input,
        accessibilityClient: accessibility,
        microphoneClient: microphone,
        settingsOpener: opener,
    )

    await viewModel.refresh()

    XCTAssertTrue(viewModel.allGranted)
}

@MainActor
func testRequestInputMonitoringOpensSettingsAndRefreshes() async {
    var requestCount = 0
    var openCount = 0

    let input = InputMonitoringPermissionClient(
        isGranted: { requestCount > 0 },
        requestAccess: { requestCount += 1; return true },
    )
    let accessibility = AccessibilityPermissionClient(
        isTrusted: { true },
        requestAccess: {},
    )
    let microphone = MicrophonePermissionClient(
        authorizationStatus: { .authorized },
        requestAccess: { true },
    )
    let opener = SystemSettingsOpener(open: { openCount += 1 })

    let viewModel = PermissionsViewModel(
        inputMonitoringClient: input,
        accessibilityClient: accessibility,
        microphoneClient: microphone,
        settingsOpener: opener,
    )

    await viewModel.requestInputMonitoringAccess()

    XCTAssertEqual(requestCount, 1)
    XCTAssertEqual(openCount, 1)
    XCTAssertTrue(viewModel.inputMonitoringGranted)
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter PermissionsViewModelTests` (from `Packages/FloxBoxCore`)
Expected: FAIL (new clients + APIs missing)

**Step 3: Write minimal implementation**

```swift
public struct InputMonitoringPermissionClient {
    public var isGranted: () -> Bool
    public var requestAccess: () -> Bool

    public init(
        isGranted: @escaping () -> Bool = { CGPreflightListenEventAccess() },
        requestAccess: @escaping () -> Bool = { CGRequestListenEventAccess() },
    ) {
        self.isGranted = isGranted
        self.requestAccess = requestAccess
    }
}

public struct MicrophonePermissionClient {
    public var authorizationStatus: () -> AVAuthorizationStatus
    public var requestAccess: () async -> Bool

    public init(
        authorizationStatus: @escaping () -> AVAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .audio)
        },
        requestAccess: @escaping () async -> Bool = {
            await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        },
    ) {
        self.authorizationStatus = authorizationStatus
        self.requestAccess = requestAccess
    }
}

public struct SystemSettingsOpener {
    public var open: () -> Void
    public init(open: @escaping () -> Void = {
        let url = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        NSWorkspace.shared.open(url)
    }) {
        self.open = open
    }
}

@MainActor
public final class PermissionsViewModel: ObservableObject {
    @Published public var inputMonitoringGranted: Bool
    @Published public var accessibilityGranted: Bool
    @Published public var microphoneGranted: Bool

    private let inputMonitoringClient: InputMonitoringPermissionClient
    private let accessibilityClient: AccessibilityPermissionClient
    private let microphoneClient: MicrophonePermissionClient
    private let settingsOpener: SystemSettingsOpener

    public init(
        inputMonitoringClient: InputMonitoringPermissionClient,
        accessibilityClient: AccessibilityPermissionClient,
        microphoneClient: MicrophonePermissionClient,
        settingsOpener: SystemSettingsOpener,
    ) {
        self.inputMonitoringClient = inputMonitoringClient
        self.accessibilityClient = accessibilityClient
        self.microphoneClient = microphoneClient
        self.settingsOpener = settingsOpener
        inputMonitoringGranted = inputMonitoringClient.isGranted()
        accessibilityGranted = accessibilityClient.isTrusted()
        microphoneGranted = microphoneClient.authorizationStatus() == .authorized
    }

    public var allGranted: Bool {
        inputMonitoringGranted && accessibilityGranted && microphoneGranted
    }

    public func refresh() async {
        inputMonitoringGranted = inputMonitoringClient.isGranted()
        accessibilityGranted = accessibilityClient.isTrusted()
        microphoneGranted = microphoneClient.authorizationStatus() == .authorized
    }

    public func requestInputMonitoringAccess() async {
        _ = inputMonitoringClient.requestAccess()
        settingsOpener.open()
        await refresh()
    }

    public func requestAccessibilityAccess() async {
        accessibilityClient.requestAccess()
        settingsOpener.open()
        await refresh()
    }

    public func requestMicrophoneAccess() async {
        _ = await microphoneClient.requestAccess()
        settingsOpener.open()
        await refresh()
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter PermissionsViewModelTests`
Expected: PASS

**Step 5: Commit**

```bash
git add \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/InputMonitoringPermissionClient.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/MicrophonePermissionClient.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/SystemSettingsOpener.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/PermissionsView.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Permissions/PermissionsViewModelTests.swift

git commit -m "feat: add permission clients for interstitial"
```

---

### Task 2: Update permissions interstitial UI + presentation

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/PermissionsView.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/PermissionsWindowController.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/App/FloxBoxAppModel.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/App/MenubarMenu.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/PermissionsViewTests.swift`

**Step 1: Write the failing test**

```swift
@MainActor
func testPermissionsViewBuildsWithNewRows() {
    let viewModel = PermissionsViewModel(
        inputMonitoringClient: .init(isGranted: { false }, requestAccess: { false }),
        accessibilityClient: .init(isTrusted: { false }, requestAccess: {}),
        microphoneClient: .init(authorizationStatus: { .denied }, requestAccess: { false }),
        settingsOpener: .init(open: {}),
    )

    _ = PermissionsView(viewModel: viewModel)
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter PermissionsViewTests`
Expected: FAIL (new init signature not wired everywhere)

**Step 3: Write minimal implementation**

- Replace interstitial layout with three required rows:
  - Input Monitoring: “Needed for push‑to‑talk hotkey detection.”
  - Accessibility: “Needed to type into other apps.”
  - Microphone: “Needed to capture dictation audio.”
- Each row’s button calls the corresponding view model request method.
- Update `PermissionsWindowController` to remove `.floating` level and use a normal window level.
- Update `FloxBoxAppModel` to construct the new view model with the new clients + opener.
- Update `MenubarMenu` to show “Permissions” if `!permissionsViewModel.allGranted`.

**Step 4: Run tests to verify they pass**

Run: `swift test --filter PermissionsViewTests`
Expected: PASS

**Step 5: Commit**

```bash
git add \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/PermissionsView.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Permissions/PermissionsWindowController.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/App/FloxBoxAppModel.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/App/MenubarMenu.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/PermissionsViewTests.swift

git commit -m "feat: update permissions interstitial layout"
```

---

### Task 3: Stop auto-requesting Input Monitoring in event tap backend

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/EventTapShortcutBackend.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Shortcuts/EventTapShortcutBackendTests.swift`

**Step 1: Update the failing test**

```swift
func testStartDoesNotRequestListenEventAccessWhenMissing() {
    var requestCount = 0
    var lastStatusMessage: String?
    let backend = EventTapShortcutBackend(
        tapFactory: { _, _, _ in nil },
        runLoop: CFRunLoopGetCurrent(),
        runLoopSourceFactory: { _ in
            var context = CFRunLoopSourceContext()
            return CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)
        },
        retryTimerFactory: { _, _ in TestRetryTimer(handler: {}) },
        listenEventAccessChecker: { false },
        listenEventAccessRequester: { requestCount += 1; return false },
    )
    backend.onStatusChange = { lastStatusMessage = $0 }

    backend.start()

    XCTAssertEqual(requestCount, 0)
    XCTAssertEqual(lastStatusMessage, "Enable Input Monitoring for FloxBox in System Settings")
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter EventTapShortcutBackendTests/testStartDoesNotRequestListenEventAccessWhenMissing`
Expected: FAIL (backend still requests)

**Step 3: Write minimal implementation**

- Remove the `listenEventAccessRequester()` call from `attemptStart()`.
- Remove `hasRequestedListenEventAccess` state (no longer needed).

**Step 4: Run tests to verify they pass**

Run: `swift test --filter EventTapShortcutBackendTests/testStartDoesNotRequestListenEventAccessWhenMissing`
Expected: PASS

**Step 5: Commit**

```bash
git add \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/EventTapShortcutBackend.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Shortcuts/EventTapShortcutBackendTests.swift

git commit -m "feat: stop auto-requesting input monitoring"
```

---

### Task 4: Add notch network spinner + cancel affordance

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Notch/NotchRecordingView.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Notch/NotchRecordingController.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Notch/NotchRecordingWindow.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift` (protocol update only)
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/NotchRecordingViewTests.swift`

**Step 1: Write the failing test**

```swift
@MainActor
func testNotchRecordingViewBuildsInAwaitingNetworkState() {
    let state = NotchRecordingState()
    state.isRecording = false
    state.isAwaitingNetwork = true
    state.showNetworkSpinner = true
    _ = NotchRecordingView(state: state)
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter NotchRecordingViewTests`
Expected: FAIL (new state fields not defined)

**Step 3: Write minimal implementation**

- Add to `NotchRecordingState`:
  - `@Published var isAwaitingNetwork = false`
  - `@Published var showNetworkSpinner = false`
  - `var onCancel: (() -> Void)?`
- Update `NotchRecordingView` to:
  - Show waveform + icon only when `isRecording`.
  - When `isAwaitingNetwork` is true, show a right-side indicator:
    - If `showNetworkSpinner` is false, show nothing.
    - If true, show a `ProgressView` that morphs to `xmark.circle.fill` on hover and calls `state.onCancel?()` on click.
- Update `NotchRecordingController`:
  - Add `showAwaitingNetwork(onCancel:)` method.
  - Start a 2s delayed Task that flips `showNetworkSpinner = true` if still awaiting.
  - Ensure the window remains visible and expanded while awaiting network.
- Update `NotchRecordingWindow` to allow mouse events when awaiting network (disable `ignoresMouseEvents` in that mode).
- Update `NotchRecordingControlling` protocol to include `showAwaitingNetwork(onCancel:)` and `showRecording()` (rename current `show()` to `showRecording()`).

**Step 4: Run tests to verify they pass**

Run: `swift test --filter NotchRecordingViewTests`
Expected: PASS

**Step 5: Commit**

```bash
git add \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Notch/NotchRecordingView.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Notch/NotchRecordingController.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Notch/NotchRecordingWindow.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/NotchRecordingViewTests.swift

git commit -m "feat: add notch network spinner and cancel"
```

---

### Task 5: Transcription network state, timeouts, cancel, and final failure notification

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Views/DebugPanelView.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/TranscriptionViewModelTests.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TranscriptionPermissionsTests.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TestDoubles.swift`

**Step 1: Write the failing tests**

```swift
@MainActor
func testRealtimeCompletionTimeoutFallsBackToRest() async {
    let realtime = TestRealtimeClient()
    let audio = TestAudioCapture()
    let rest = TestRestClient()
    rest.queueResults([.success("Rest OK")])
    let overlay = TestNotchOverlay()

    let viewModel = TranscriptionViewModel(
        keychain: InMemoryKeychainStore(),
        audioCapture: audio,
        realtimeFactory: { _ in realtime },
        restClient: rest,
        microphoneChecker: { true },
        notchOverlay: overlay,
        realtimeCompletionTimeoutNanos: 1_000_000,
        restTimeoutNanos: 1_000_000,
        pttTailNanos: 0,
        accessibilityChecker: { true },
        secureInputChecker: { false },
        permissionsPresenter: {},
        dictationInjector: TestDictationInjector(),
        clipboardWriter: { _ in },
    )

    viewModel.apiKeyInput = "sk-test"
    await viewModel.startAndWait()
    audio.emit(Data([0x01]))
    await Task.yield()

    await viewModel.stopAndWait()
    try? await Task.sleep(nanoseconds: 5_000_000)

    XCTAssertEqual(rest.callCount, 1)
    XCTAssertEqual(viewModel.transcript, "Rest OK")
    XCTAssertEqual(viewModel.status, .idle)
    XCTAssertEqual(overlay.hideCount, 1)
}

@MainActor
func testFinalRestFailureNotifiesAndReturnsIdle() async {
    let realtime = TestRealtimeClient()
    let audio = TestAudioCapture()
    let rest = TestRestClient()
    rest.queueResults([.failure(TestRestError.failure), .failure(TestRestError.failure)])
    let toast = TestToastPresenter()

    let viewModel = TranscriptionViewModel(
        keychain: InMemoryKeychainStore(),
        audioCapture: audio,
        realtimeFactory: { _ in realtime },
        restClient: rest,
        microphoneChecker: { true },
        notchOverlay: TestNotchOverlay(),
        toastPresenter: toast,
        restRetryDelayNanos: 1_000_000,
        restTimeoutNanos: 1_000_000,
        pttTailNanos: 0,
        accessibilityChecker: { true },
        secureInputChecker: { false },
        permissionsPresenter: {},
        dictationInjector: TestDictationInjector(),
        clipboardWriter: { _ in },
    )

    viewModel.apiKeyInput = "sk-test"
    await viewModel.startAndWait()
    audio.emit(Data([0x01]))
    await Task.yield()

    realtime.emit(.error("socket failed"))
    await viewModel.stopAndWait()
    try? await Task.sleep(nanoseconds: 5_000_000)

    XCTAssertEqual(rest.callCount, 2)
    XCTAssertEqual(toast.toastMessages.last, "Dictation failed — check your network")
    XCTAssertTrue(toast.actionTitles.isEmpty)
    XCTAssertEqual(viewModel.status, .idle)
}

@MainActor
func testCancelStopsPendingNetworkAndReturnsIdle() async {
    let realtime = TestRealtimeClient()
    let audio = TestAudioCapture()
    let rest = TestRestClient()
    let overlay = TestNotchOverlay()

    let viewModel = TranscriptionViewModel(
        keychain: InMemoryKeychainStore(),
        audioCapture: audio,
        realtimeFactory: { _ in realtime },
        restClient: rest,
        microphoneChecker: { true },
        notchOverlay: overlay,
        realtimeCompletionTimeoutNanos: 5_000_000_000,
        restTimeoutNanos: 5_000_000_000,
        pttTailNanos: 0,
        accessibilityChecker: { true },
        secureInputChecker: { false },
        permissionsPresenter: {},
        dictationInjector: TestDictationInjector(),
        clipboardWriter: { _ in },
    )

    viewModel.apiKeyInput = "sk-test"
    await viewModel.startAndWait()
    audio.emit(Data([0x01]))
    await Task.yield()
    await viewModel.stopAndWait()

    overlay.triggerCancel()
    try? await Task.sleep(nanoseconds: 1_000_000)

    XCTAssertEqual(viewModel.status, .idle)
    XCTAssertEqual(overlay.hideCount, 1)
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter TranscriptionViewModelTests/testRealtimeCompletionTimeoutFallsBackToRest`
Expected: FAIL (new behavior not implemented)

**Step 3: Write minimal implementation**

- Add `RecordingStatus.awaitingNetwork` and update `label` to include a human-friendly string.
- Extend `NotchRecordingControlling` usages to call `showRecording()` on start and `showAwaitingNetwork(onCancel:)` when finishing.
- Add new injected timeouts:
  - `realtimeCompletionTimeoutNanos` default `5_000_000_000`.
  - `restTimeoutNanos` default `5_000_000_000`.
- Add helpers:
  - `beginAwaitingNetwork()` sets status, shows notch spinner after delay, and installs cancel handler.
  - `endAwaitingNetwork()` clears state, hides notch, and sets `status = .idle`.
  - `cancelPendingNetwork()` closes realtime, cancels rest retries/timeouts, clears pending WAV, ends awaiting network, and finalizes injection if needed.
- Start a completion timeout task after commit when waiting for realtime completion; on timeout, close realtime and run REST fallback.
- Wrap REST transcription in a timeout; on failure, wait 2s and retry once; on final failure, call `toastPresenter.showToast("Dictation failed — check your network")` and return to idle.
- Remove the manual retry action from REST fallback.
- Ensure `start()` ignores calls when `status == .awaitingNetwork`.
- Update tests and test doubles for new initializer arguments and notch overlay methods.

**Step 4: Run tests to verify they pass**

Run:
- `swift test --filter TranscriptionViewModelTests/testRealtimeCompletionTimeoutFallsBackToRest`
- `swift test --filter TranscriptionViewModelTests/testFinalRestFailureNotifiesAndReturnsIdle`
- `swift test --filter TranscriptionViewModelTests/testCancelStopsPendingNetworkAndReturnsIdle`

Expected: PASS

**Step 5: Commit**

```bash
git add \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Views/DebugPanelView.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/TranscriptionViewModelTests.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TranscriptionPermissionsTests.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TestDoubles.swift

git commit -m "feat: add network timeouts and cancel flow"
```

---

### Task 6: Full test pass

**Step 1: Run full test suite**

Run: `swift test` (from `Packages/FloxBoxCore`)
Expected: PASS

**Step 2: Commit (if needed)**

If any snapshot or test updates were required during the full run, commit them here.

---

Plan complete and saved to `docs/plans/2026-01-27-permissions-interstitial-network-notch-implementation.md`.

Two execution options:

1. Subagent-Driven (this session) — I dispatch fresh subagent per task, review between tasks, fast iteration.
2. Parallel Session (separate) — Open new session with executing-plans, batch execution with checkpoints.

Which approach?
