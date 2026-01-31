# Format-While-Recording Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Format transcription during recording so the final paste waits only on the tail chunk, enabling ≥200 wpm while keeping always-on formatting.

**Architecture:** Disable VAD and manually commit audio every 1000 ms. Buffer completed segments into formatting-sized chunks, format each chunk in parallel during recording, and build a formatted transcript store. On stop, flush remaining buffer and insert the formatted transcript.

**Tech Stack:** Swift, AsyncStream, URLSession, Swift Concurrency, existing FormattingPipeline/FormatValidator, XCTest.

---

### Task 1: FormattingBuffer (buffering + cue detection)

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/FormattingBuffer.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/FormattingBufferTests.swift`

**Step 1: Write the failing test**

```swift
@testable import FloxBoxCore
import XCTest

final class FormattingBufferTests: XCTestCase {
    func testEmitsChunkWhenWordThresholdMet() {
        let buffer = FormattingBuffer(minWords: 12, maxWords: 20)
        let chunk1 = buffer.append(text: "This is a short segment")
        XCTAssertNil(chunk1)

        let chunk2 = buffer.append(text: "that should push the word count over the limit")
        XCTAssertEqual(chunk2?.text, "This is a short segment that should push the word count over the limit")
    }

    func testEmitsChunkOnTopicShiftCue() {
        let buffer = FormattingBuffer(minWords: 12, maxWords: 20)
        _ = buffer.append(text: "We should keep pricing as is")
        let chunk = buffer.append(text: "Next, check with support about refunds")
        XCTAssertTrue(chunk?.text.contains("Next,"))
    }

    func testFlushReturnsPendingText() {
        let buffer = FormattingBuffer(minWords: 12, maxWords: 20)
        _ = buffer.append(text: "Small remaining tail")
        XCTAssertEqual(buffer.flush()?.text, "Small remaining tail")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter FormattingBufferTests`

Expected: FAIL (FormattingBuffer not found).

**Step 3: Write minimal implementation**

```swift
public struct FormattingChunk: Equatable {
    public let text: String
}

public final class FormattingBuffer {
    private let minWords: Int
    private let maxWords: Int
    private var parts: [String] = []

    private let cueWords: [String] = ["next", "also", "new paragraph", "on another note"]

    public init(minWords: Int = 12, maxWords: Int = 20) {
        self.minWords = minWords
        self.maxWords = maxWords
    }

    public func append(text: String) -> FormattingChunk? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        parts.append(trimmed)
        let combined = parts.joined(separator: " ")
        let wordCount = combined.split(whereSeparator: { $0.isWhitespace }).count
        if wordCount >= maxWords || (wordCount >= minWords && containsCue(trimmed)) {
            parts.removeAll()
            return FormattingChunk(text: combined)
        }
        return nil
    }

    public func flush() -> FormattingChunk? {
        guard !parts.isEmpty else { return nil }
        let combined = parts.joined(separator: " ")
        parts.removeAll()
        return FormattingChunk(text: combined)
    }

    private func containsCue(_ text: String) -> Bool {
        let lower = text.lowercased()
        return cueWords.contains { lower.contains($0) }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/FloxBoxCore --filter FormattingBufferTests`

Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/FormattingBuffer.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/FormattingBufferTests.swift
git commit -m "feat: add formatting buffer for chunking"
```

---

### Task 2: FormattedTranscriptStore (ordered formatted output)

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/FormattedTranscriptStore.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/FormattedTranscriptStoreTests.swift`

**Step 1: Write the failing test**

```swift
@testable import FloxBoxCore
import XCTest

final class FormattedTranscriptStoreTests: XCTestCase {
    func testAppendsChunksWithSpacing() {
        let store = FormattedTranscriptStore()
        store.append("Hello.")
        store.append("World.")
        XCTAssertEqual(store.displayText, "Hello. World.")
    }

    func testPreservesBlankLines() {
        let store = FormattedTranscriptStore()
        store.append("First paragraph.\n\nSecond paragraph.")
        store.append("Third sentence.")
        XCTAssertEqual(store.displayText, "First paragraph.\n\nSecond paragraph. Third sentence.")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter FormattedTranscriptStoreTests`

Expected: FAIL (FormattedTranscriptStore not found).

**Step 3: Write minimal implementation**

```swift
public final class FormattedTranscriptStore {
    private var chunks: [String] = []

    public init() {}

    public func append(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        chunks.append(trimmed)
    }

    public var displayText: String {
        var output = ""
        for chunk in chunks {
            if output.isEmpty {
                output = chunk
                continue
            }
            if shouldInsertSpace(between: output, and: chunk) {
                output.append(" ")
            }
            output.append(chunk)
        }
        return output
    }

    private func shouldInsertSpace(between existing: String, and next: String) -> Bool {
        guard let last = existing.last, let first = next.first else { return false }
        if last.isWhitespace || first.isWhitespace { return false }
        if ".,!?;:)]}".contains(first) { return false }
        if "([{".contains(last) { return false }
        return true
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/FloxBoxCore --filter FormattedTranscriptStoreTests`

Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/FormattedTranscriptStore.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/FormattedTranscriptStoreTests.swift
git commit -m "feat: add formatted transcript store"
```

---

### Task 3: Manual commit ticker (1s cadence)

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/TranscriptionViewModelTests.swift`

**Step 1: Write the failing test**

```swift
func testStartUsesManualCommitWhenFormatWhileRecordingEnabled() async {
    let realtime = TestRealtimeClient()
    let viewModel = TranscriptionViewModel(
        keychain: InMemoryKeychainStore(),
        audioCapture: TestAudioCapture(),
        realtimeFactory: { _ in realtime },
        restClient: TestRestClient(),
        permissionRequester: { true },
        notchOverlay: TestNotchOverlay(),
        toastPresenter: TestToastPresenter(),
        pttTailNanos: 0,
        accessibilityChecker: { true },
        secureInputChecker: { false },
        permissionsPresenter: {},
        dictationInjector: TestDictationInjector(),
        clipboardWriter: { _ in }
    )

    viewModel.apiKeyInput = "sk-test"
    await viewModel.startAndWait()

    XCTAssertEqual(viewModel.vadMode, .off)
    XCTAssertEqual(viewModel.manualCommitInterval, .seconds(1))
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter testStartUsesManualCommitWhenFormatWhileRecordingEnabled`

Expected: FAIL (vadMode/manualCommitInterval not forced).

**Step 3: Implement minimal code**
- In `startInternal()`, set a dedicated recording config:
  - `recordingVADMode = .off`
  - `recordingCommitInterval = .seconds(1)` (new private var) and use it in `startCommitTimerIfNeeded`.

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/FloxBoxCore --filter testStartUsesManualCommitWhenFormatWhileRecordingEnabled`

Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/TranscriptionViewModelTests.swift
git commit -m "feat: force 1s manual commit for format-while-recording"
```

---

### Task 4: Incremental formatting pipeline integration

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/TranscriptionViewModelTests.swift`
- Use: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TestDoubles.swift` (TestFormattingClient)

**Step 1: Write the failing test**

```swift
func testFormatsChunksDuringRecordingAndInsertsFormattedOutput() async {
    let realtime = TestRealtimeClient()
    let audio = TestAudioCapture()
    let injector = TestDictationInjector()
    let formattingClient = TestFormattingClient(results: [
        .success("First formatted."),
        .success("Second formatted."),
    ])
    let formattingSettings = FormattingSettingsStore(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
    formattingSettings.isEnabled = true

    let viewModel = TranscriptionViewModel(
        keychain: InMemoryKeychainStore(),
        audioCapture: audio,
        realtimeFactory: { _ in realtime },
        restClient: TestRestClient(),
        permissionRequester: { true },
        notchOverlay: TestNotchOverlay(),
        toastPresenter: TestToastPresenter(),
        pttTailNanos: 0,
        accessibilityChecker: { true },
        secureInputChecker: { false },
        permissionsPresenter: {},
        dictationInjector: injector,
        clipboardWriter: { _ in },
        formattingSettings: formattingSettings,
        formattingClientFactory: { _ in formattingClient }
    )

    viewModel.apiKeyInput = "sk-test"
    await viewModel.startAndWait()

    realtime.emit(.inputAudioCommitted(.init(itemId: "item-1", previousItemId: nil)))
    realtime.emit(.transcriptionCompleted(.init(itemId: "item-1", contentIndex: 0, transcript: "First raw")))
    realtime.emit(.inputAudioCommitted(.init(itemId: "item-2", previousItemId: "item-1")))
    realtime.emit(.transcriptionCompleted(.init(itemId: "item-2", contentIndex: 0, transcript: "Second raw")))

    await viewModel.stopAndWait()

    XCTAssertEqual(injector.insertedTexts.last, "First formatted. Second formatted. ")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter testFormatsChunksDuringRecordingAndInsertsFormattedOutput`

Expected: FAIL (no incremental formatting). 

**Step 3: Implement minimal code**
- Add `FormattingBuffer` + `FormattedTranscriptStore` properties to `TranscriptionViewModel`.
- On `transcription_completed`:
  - append raw to `TranscriptStore` (unchanged)
  - feed into `FormattingBuffer`
  - when a chunk is produced, call `formatChunk()` (new async helper)
- `formatChunk()` uses `FormattingPipeline` and appends to `FormattedTranscriptStore`.
- At `stopInternal`, force a final commit, flush buffer, await final formatting task, then call `insertFinalTranscriptIfNeeded(text: formattedStore.displayText, wasFormatted: true)`.

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/FloxBoxCore --filter testFormatsChunksDuringRecordingAndInsertsFormattedOutput`

Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/TranscriptionViewModelTests.swift
git commit -m "feat: format transcript chunks during recording"
```

---

### Task 5: Session timing + WPM logging

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift`

**Step 1: Add timing fields**
- Track `recordingStartUptime`, `firstTextUptime`, `insertUptime`.

**Step 2: Log WPM after insertion**
- When final insertion happens, compute:
  - `wordCount = formattedText.split(whereSeparator: { $0.isWhitespace }).count`
  - `wpm = wordCount / (insertUptime - recordingStartUptime) * 60`
- Log with `DebugLog.recording("wpm=... session=...")`.

**Step 3: Manual verification**
- Run a short dictation and confirm logs appear with expected WPM values.

**Step 4: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift
git commit -m "feat: log wpm timing for dictation sessions"
```

---

## Execution Handoff
Plan complete and saved to `docs/plans/2026-01-31-format-while-recording-implementation.md`.

Two execution options:

1. **Subagent-Driven (this session)** – I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Parallel Session (separate)** – Open new session with executing-plans, batch execution with checkpoints.

Which approach do you want?
