# Fast Formatting Latency Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Minimize transcript post‑processing latency with GPT‑5 series formatting and add notch feedback during formatting.

**Architecture:** Keep audio transcription on the dedicated speech‑to‑text model; run formatting as a separate text‑only pass using GPT‑5‑nano with low reasoning effort. Add a formatting state to the notch overlay so users see a spinner while formatting runs. Ensure request payloads stay within GPT‑5 parameter constraints and preserve current retry/error handling.

**Tech Stack:** Swift, SwiftUI, URLSession, OpenAI Responses API.

### Task 1: Add reasoning effort to formatting requests

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/FormattingModel.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/FormattingClient.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/FormattingClientTests.swift`

**Step 1: Write the failing test**

```swift
func testFormattingClientIncludesReasoningEffortForGpt5Nano() async throws {
    let recorder = RequestRecorder()
    let session = URLSession(configuration: recorder.configuration)
    let client = OpenAIFormattingClient(apiKey: "sk-test", session: session)

    _ = try await client.format(text: "Raw", model: .gpt5Nano, glossary: [])

    XCTAssertTrue(recorder.lastBodyString?.contains("\"reasoning\":{\"effort\":\"minimal\"}") == true)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter FormattingClientTests.testFormattingClientIncludesReasoningEffortForGpt5Nano`
Expected: FAIL because request body has no reasoning block.

**Step 3: Write minimal implementation**

```swift
// FormattingModel.swift
var reasoningEffort: String { /* map nano/mini -> minimal, gpt-5.2 -> none */ }

// FormattingClient.swift
struct ResponseRequest: Encodable {
    let model: String
    let input: String
    let reasoning: ReasoningOptions
}

struct ReasoningOptions: Encodable { let effort: String }
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter FormattingClientTests.testFormattingClientIncludesReasoningEffortForGpt5Nano`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/FormattingModel.swift \
        Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/FormattingClient.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/FormattingClientTests.swift

git commit -m "feat: set reasoning effort for GPT-5 formatting"
```

### Task 2: Add notch formatting spinner state

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Notch/NotchRecordingView.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Notch/NotchRecordingController.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/NotchRecordingViewTests.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TestDoubles.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/TranscriptionViewModelTests.swift`

**Step 1: Write the failing test**

```swift
@MainActor
func testNotchRecordingViewBuildsInFormattingState() {
    let state = NotchRecordingState()
    state.isFormatting = true
    _ = NotchRecordingView(state: state)
}
```

```swift
func testStopFormatsTranscriptShowsNotchFormattingIndicator() async {
    let realtime = TestRealtimeClient()
    let audio = TestAudioCapture()
    let toast = TestToastPresenter()
    let injector = TestDictationInjector()
    let keychain = InMemoryKeychainStore()
    let settingsDefaults = UserDefaults(suiteName: UUID().uuidString)!
    let formattingSettings = FormattingSettingsStore(userDefaults: settingsDefaults)
    let glossaryStore = PersonalGlossaryStore(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
    let formattingClient = TestFormattingClient(results: [.success("Raw text.")])
    let overlay = TestNotchOverlay()

    let viewModel = TranscriptionViewModel(
        keychain: keychain,
        audioCapture: audio,
        realtimeFactory: { _ in realtime },
        restClient: TestRestClient(),
        permissionRequester: { true },
        notchOverlay: overlay,
        toastPresenter: toast,
        pttTailNanos: 0,
        accessibilityChecker: { true },
        secureInputChecker: { false },
        permissionsPresenter: {},
        dictationInjector: injector,
        clipboardWriter: { _ in },
        formattingSettings: formattingSettings,
        glossaryStore: glossaryStore,
        formattingClientFactory: { _ in formattingClient }
    )

    viewModel.apiKeyInput = "sk-test"
    await viewModel.startAndWait()
    audio.emit(Data([0x01]))

    await viewModel.stopAndWait()
    realtime.emit(.inputAudioCommitted(.init(itemId: "item1", previousItemId: nil)))
    realtime.emit(.transcriptionCompleted(.init(itemId: "item1", contentIndex: 0, transcript: "Raw text")))
    try? await Task.sleep(nanoseconds: 50_000_000)

    XCTAssertEqual(overlay.showFormattingCount, 1)
    XCTAssertGreaterThanOrEqual(overlay.hideCount, 1)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter NotchRecordingViewTests.testNotchRecordingViewBuildsInFormattingState`
Expected: FAIL due to missing isFormatting state.

Run: `swift test --filter TranscriptionViewModelTests.testStopFormatsTranscriptShowsNotchFormattingIndicator`
Expected: FAIL because formatting state is never shown.

**Step 3: Write minimal implementation**

```swift
// NotchRecordingState
@Published var isFormatting = false

// NotchRecordingView
.overlay(alignment: .trailing) {
    if state.isFormatting {
        ProgressView().progressViewStyle(.circular).tint(.white.opacity(0.85))
            .frame(width: 16, height: 16)
            .padding(.trailing, 12)
    }
}

// NotchRecordingController
func showFormatting() { /* set isFormatting true, open notch */ }

// TranscriptionViewModel
notchOverlay.showFormatting() at formatting start; hide when done
```

**Step 4: Run tests to verify they pass**

Run:
- `swift test --filter NotchRecordingViewTests.testNotchRecordingViewBuildsInFormattingState`
- `swift test --filter TranscriptionViewModelTests.testStopFormatsTranscriptShowsNotchFormattingIndicator`

Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Notch/NotchRecordingView.swift \
        Packages/FloxBoxCore/Sources/FloxBoxCore/Notch/NotchRecordingController.swift \
        Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/NotchRecordingViewTests.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TestDoubles.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/TranscriptionViewModelTests.swift

git commit -m "feat: show notch spinner during formatting"
```

### Task 3: Verify formatting latency choice and document

**Files:**
- Modify: `docs/plans/2026-01-30-fast-formatting-latency.md`

**Step 1: Document benchmark results**

```markdown
## Benchmark (local, Responses API)
- gpt-5-nano (reasoning=minimal): ~0.86s avg
- gpt-5.2 (reasoning=none): ~1.11s avg
- gpt-5-mini (reasoning=minimal): ~1.34s avg
```

**Step 2: Commit**

```bash
git add docs/plans/2026-01-30-fast-formatting-latency.md

git commit -m "docs: add formatting latency benchmark results"
```
