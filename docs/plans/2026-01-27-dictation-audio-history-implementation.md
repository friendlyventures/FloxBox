# Dictation Audio History Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Persist and display the last five dictation sessions with wire-audio chunks (server commit boundaries) and per-session playback in the Debug panel.

**Architecture:** Add a disk-backed history store for sessions/chunks, a recorder that appends only successfully sent PCM to WAV files and finalizes on server commit events, and a playback controller to drive per-session Play All with active-chunk highlighting. `TranscriptionViewModel` owns the recorder and exposes sessions for SwiftUI.

**Tech Stack:** Swift, SwiftUI, Observation, AVFoundation (AVAudioPlayer), FileManager, Codable JSON, WavFileWriter.

---

### Task 1: Disk-backed history models + store

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/DictationAudioHistoryStore.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/DictationAudioHistoryStoreTests.swift`

**Step 1: Write the failing test**

```swift
@testable import FloxBoxCore
import XCTest

final class DictationAudioHistoryStoreTests: XCTestCase {
    func testStorePersistsAndLoadsSessions() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DictationAudioHistoryStore(baseURL: base)

        let session = DictationSessionRecord(
            id: "session-1",
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            chunks: [DictationChunkRecord(
                id: "item-1",
                createdAt: Date(timeIntervalSince1970: 1.5),
                wavPath: "session-1/chunk-001.wav",
                byteCount: 4,
                transcript: "Hello",
            )]
        )

        try store.save([session])
        let loaded = try store.load()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, "session-1")
        XCTAssertEqual(loaded.first?.chunks.first?.transcript, "Hello")
    }

    func testStoreKeepsLastFiveSessions() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DictationAudioHistoryStore(baseURL: base)

        let sessions = (1...6).map { index in
            DictationSessionRecord(
                id: "session-\(index)",
                startedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                endedAt: nil,
                chunks: []
            )
        }

        try store.save(sessions)
        let loaded = try store.load()

        XCTAssertEqual(loaded.count, 5)
        XCTAssertEqual(loaded.first?.id, "session-6")
        XCTAssertEqual(loaded.last?.id, "session-2")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter DictationAudioHistoryStoreTests` (from `Packages/FloxBoxCore`)
Expected: FAIL with “Use of unresolved identifier 'DictationAudioHistoryStore'”.

**Step 3: Write minimal implementation**

```swift
public struct DictationSessionRecord: Codable, Identifiable {
    public var id: String
    public var startedAt: Date
    public var endedAt: Date?
    public var chunks: [DictationChunkRecord]
}

public struct DictationChunkRecord: Codable, Identifiable {
    public var id: String
    public var createdAt: Date
    public var wavPath: String
    public var byteCount: Int
    public var transcript: String
}

public final class DictationAudioHistoryStore {
    private let baseURL: URL
    private let indexURL: URL
    private let maxSessions = 5

    public init(baseURL: URL = Self.defaultBaseURL()) {
        self.baseURL = baseURL
        self.indexURL = baseURL.appendingPathComponent("history.json")
    }

    public func load() throws -> [DictationSessionRecord] { /* read + decode + filter missing files */ }
    public func save(_ sessions: [DictationSessionRecord]) throws { /* trim, encode, write */ }

    private static func defaultBaseURL() -> URL { /* Application Support/FloxBox/Debug/DictationHistory */ }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter DictationAudioHistoryStoreTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/DictationAudioHistoryStore.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/DictationAudioHistoryStoreTests.swift

git commit -m "feat: add dictation audio history store"
```

---

### Task 2: Wire-audio recorder + TranscriptionViewModel integration

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/WireAudioHistoryRecorder.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TestDoubles.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TranscriptionViewModelTests.swift`

**Step 1: Write the failing test**

```swift
@MainActor
func testWireAudioHistoryCreatesChunkOnCommit() async throws {
    let realtime = TestRealtimeClient()
    let audio = TestAudioCapture()
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = DictationAudioHistoryStore(baseURL: base)

    let viewModel = TranscriptionViewModel(
        keychain: InMemoryKeychainStore(),
        audioCapture: audio,
        realtimeFactory: { _ in realtime },
        restClient: TestRestClient(),
        permissionRequester: { true },
        notchOverlay: TestNotchOverlay(),
        pttTailNanos: 0,
        accessibilityChecker: { true },
        secureInputChecker: { false },
        permissionsPresenter: {},
        dictationInjector: TestDictationInjector(),
        clipboardWriter: { _ in },
        audioHistoryStore: store
    )

    viewModel.apiKeyInput = "sk-test"
    await viewModel.startAndWait()
    audio.emit(Data([0x01, 0x02]))
    await Task.yield()

    realtime.emit(.inputAudioCommitted(.init(itemId: "item-1", previousItemId: nil)))
    realtime.emit(.transcriptionCompleted(.init(itemId: "item-1", contentIndex: 0, transcript: "Hello")))
    try? await Task.sleep(nanoseconds: 5_000_000)

    let sessions = viewModel.dictationAudioHistorySessions
    XCTAssertEqual(sessions.count, 1)
    XCTAssertEqual(sessions.first?.chunks.first?.id, "item-1")
    XCTAssertEqual(sessions.first?.chunks.first?.transcript, "Hello")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter TranscriptionViewModelTests/testWireAudioHistoryCreatesChunkOnCommit`
Expected: FAIL (missing history store/recorder integration).

**Step 3: Write minimal implementation**

- Add `audioHistoryStore` injectable parameter to `TranscriptionViewModel.init`.
- Add `public var dictationAudioHistorySessions: [DictationSessionRecord] = []`.
- Create `WireAudioHistoryRecorder` actor with methods:
  - `startSession(sessionID: String, startedAt: Date)`
  - `appendSentAudio(_ data: Data)`
  - `commit(itemId: String, createdAt: Date)`
  - `updateTranscript(itemId: String, text: String)`
  - `endSession(endedAt: Date)`
- The recorder uses `WavFileWriter` to write `chunk-###.wav` under a session directory and updates the store.
- Update `TranscriptionViewModel`:
  - On `beginDictationSession()`: `await recorder.startSession(...)`.
  - In `scheduleAudioSend`: after `try await client.sendAudio(data)`, call `await recorder.appendSentAudio(data)`.
  - In `handleInputAudioCommitted`: call `await recorder.commit(itemId: ...)`.
  - In `handleTranscriptionCompleted`: call `await recorder.updateTranscript(itemId:text:)`.
  - In `stopInternal`: call `await recorder.endSession(endedAt:)` (also finalize any open chunk).
- After each recorder update, refresh `dictationAudioHistorySessions` on the main actor with the store’s latest sessions.

**Step 4: Run test to verify it passes**

Run: `swift test --filter TranscriptionViewModelTests/testWireAudioHistoryCreatesChunkOnCommit`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/WireAudioHistoryRecorder.swift \
        Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TranscriptionViewModelTests.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TestDoubles.swift

git commit -m "feat: record wire audio history in view model"
```

---

### Task 3: Ensure history records only successful sends

**Files:**
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TestDoubles.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TranscriptionViewModelTests.swift`

**Step 1: Write the failing test**

```swift
@MainActor
func testWireAudioHistorySkipsFailedSend() async throws {
    let realtime = FailingRealtimeClient()
    let audio = TestAudioCapture()
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = DictationAudioHistoryStore(baseURL: base)

    let viewModel = TranscriptionViewModel(
        keychain: InMemoryKeychainStore(),
        audioCapture: audio,
        realtimeFactory: { _ in realtime },
        restClient: TestRestClient(),
        permissionRequester: { true },
        notchOverlay: TestNotchOverlay(),
        pttTailNanos: 0,
        accessibilityChecker: { true },
        secureInputChecker: { false },
        permissionsPresenter: {},
        dictationInjector: TestDictationInjector(),
        clipboardWriter: { _ in },
        audioHistoryStore: store
    )

    viewModel.apiKeyInput = "sk-test"
    await viewModel.startAndWait()
    audio.emit(Data([0x01, 0x02]))
    await Task.yield()

    realtime.emit(.inputAudioCommitted(.init(itemId: "item-1", previousItemId: nil)))
    try? await Task.sleep(nanoseconds: 5_000_000)

    let sessions = viewModel.dictationAudioHistorySessions
    XCTAssertTrue(sessions.first?.chunks.first?.byteCount ?? 0 == 0)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter TranscriptionViewModelTests/testWireAudioHistorySkipsFailedSend`
Expected: FAIL

**Step 3: Write minimal implementation**

- Add `FailingRealtimeClient` test double that throws in `sendAudio`.
- Ensure the recorder is called **only after** `sendAudio` succeeds (inside `do` block).
- On commit with no appended bytes, finalize the chunk with `byteCount == 0` or skip creating a chunk record.

**Step 4: Run test to verify it passes**

Run: `swift test --filter TranscriptionViewModelTests/testWireAudioHistorySkipsFailedSend`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TestDoubles.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TranscriptionViewModelTests.swift \
        Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift

git commit -m "test: ensure wire history only records successful sends"
```

---

### Task 4: Playback controller for per-session Play All

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Audio/WireAudioPlaybackController.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Audio/WireAudioPlaybackControllerTests.swift`

**Step 1: Write the failing test**

```swift
@testable import FloxBoxCore
import XCTest

final class WireAudioPlaybackControllerTests: XCTestCase {
    func testPlayAllAdvancesActiveChunk() throws {
        let controller = WireAudioPlaybackController(player: TestAudioPlayer())
        let session = DictationSessionRecord(
            id: "session-1",
            startedAt: Date(),
            endedAt: Date(),
            chunks: [
                DictationChunkRecord(id: "item-1", createdAt: Date(), wavPath: "a.wav", byteCount: 2, transcript: ""),
                DictationChunkRecord(id: "item-2", createdAt: Date(), wavPath: "b.wav", byteCount: 2, transcript: ""),
            ]
        )

        controller.playAll(session: session, baseURL: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(controller.activeChunkID, "item-1")

        controller.simulateFinish()
        XCTAssertEqual(controller.activeChunkID, "item-2")

        controller.simulateFinish()
        XCTAssertNil(controller.activeChunkID)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter WireAudioPlaybackControllerTests`
Expected: FAIL (missing controller).

**Step 3: Write minimal implementation**

- Define `WireAudioPlaybackController` as `@MainActor @Observable` with:
  - `activeSessionID`, `activeChunkID`, `isPlaying`
  - `playAll(session:baseURL:)`, `playChunk(session:chunk:baseURL:)`, `stop()`
- Add a tiny `AudioPlaying` protocol and wrapper around `AVAudioPlayer` for real playback.
- For tests, add `TestAudioPlayer` that triggers a completion callback.

**Step 4: Run test to verify it passes**

Run: `swift test --filter WireAudioPlaybackControllerTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Audio/WireAudioPlaybackController.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Audio/WireAudioPlaybackControllerTests.swift

git commit -m "feat: add wire audio playback controller"
```

---

### Task 5: Debug panel UI for history + playback

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Views/DebugPanelView.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift`
- Test (optional smoke): `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/DebugPanelViewTests.swift`

**Step 1: Write the failing test (optional smoke)**

```swift
@MainActor
func testDebugPanelBuildsWithAudioHistory() {
    let model = FloxBoxAppModel.preview(configuration: .appStore)
    model.viewModel.dictationAudioHistorySessions = [
        DictationSessionRecord(id: "session", startedAt: Date(), endedAt: Date(), chunks: [])
    ]
    _ = DebugPanelView(model: model)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter DebugPanelViewTests/testDebugPanelBuildsWithAudioHistory`
Expected: FAIL (missing property/section).

**Step 3: Write minimal implementation**

- Add `public let wireAudioPlayback = WireAudioPlaybackController()` to `TranscriptionViewModel`.
- In `DebugPanelView`, add a new GroupBox below “Transcription Prompt”:
  - For each session, show header + “Play All”.
  - For each chunk, show Play button + transcript view.
  - Highlight active chunk when `wireAudioPlayback.activeChunkID == chunk.id`.
- Use `TextEditor` with `.disabled(true)` or a `ScrollView` + `Text` for read-only transcript.

**Step 4: Run test to verify it passes**

Run: `swift test --filter DebugPanelViewTests/testDebugPanelBuildsWithAudioHistory`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Views/DebugPanelView.swift \
        Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/DebugPanelViewTests.swift

git commit -m "feat: show dictation audio history in debug panel"
```

---

### Task 6: Full test pass

**Step 1: Run full test suite**

Run: `swift test` (from `Packages/FloxBoxCore`)
Expected: PASS

**Step 2: Commit (if needed)**

```bash
git add -A
git commit -m "chore: finalize dictation audio history"
```

---

Plan complete and saved to `docs/plans/2026-01-27-dictation-audio-history-implementation.md`. Two execution options:

1. Subagent-Driven (this session)
2. Parallel Session (separate)

Which approach?
