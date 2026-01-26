# PTT Realtime + REST Retry Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Push-to-talk always yields a completed transcription; if realtime fails, auto-retry once via REST with a saved WAV, then offer manual retry; keep only the latest WAV.

**Architecture:** Realtime is primary with VAD disabled and explicit commit on release. Audio is always captured locally to a WAV. On realtime error/timeout, fallback to REST `/v1/audio/transcriptions` with a single auto-retry and a notch action for manual retry.

**Tech Stack:** Swift 6.2, AVFoundation, URLSession, OpenAI Realtime WebSocket, REST audio transcriptions.

**Note:** Implement on `main` (no worktree) per user instruction.

---

### Task 1: Add transcript append helper for REST fallback

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptStore.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TranscriptStoreTests.swift`

**Step 1: Write the failing test**

```swift
func testAppendFinalTextAddsNewFinalSegment() {
    let store = TranscriptStore()
    store.appendFinalText("Hello")
    XCTAssertEqual(store.displayText, "Hello")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter TranscriptStoreTests/testAppendFinalTextAddsNewFinalSegment`  
Expected: FAIL (missing method)

**Step 3: Write minimal implementation**

```swift
public func appendFinalText(_ text: String, id: String = UUID().uuidString) {
    applyCompleted(.init(itemId: id, contentIndex: 0, transcript: text))
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter TranscriptStoreTests/testAppendFinalTextAddsNewFinalSegment`  
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptStore.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TranscriptStoreTests.swift
git commit -m "feat: add transcript append helper for REST fallback"
```

---

### Task 2: Add WAV writer with latest-only retention

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Audio/WavFileWriter.swift`
- Create: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Audio/WavFileWriterTests.swift`

**Step 1: Write the failing test**

```swift
func testWavWriterCreatesValidHeaderAndSize() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ptt.wav")
    let writer = WavFileWriter(url: url, sampleRate: 24_000, channels: 1)
    writer.append(Data([0x01, 0x02, 0x03, 0x04]))
    try writer.finalize()

    let data = try Data(contentsOf: url)
    XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
    XCTAssertEqual(data.count, 44 + 4)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter WavFileWriterTests/testWavWriterCreatesValidHeaderAndSize`  
Expected: FAIL (type not found)

**Step 3: Write minimal implementation**

- Write placeholder WAV header on init (44 bytes).
- Append raw PCM16 bytes.
- On `finalize()`, seek and patch RIFF and data chunk sizes.

**Step 4: Run test to verify it passes**

Run: `swift test --filter WavFileWriterTests/testWavWriterCreatesValidHeaderAndSize`  
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Audio/WavFileWriter.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Audio/WavFileWriterTests.swift
git commit -m "feat: add wav writer for ptt fallback"
```

---

### Task 3: Add REST transcription client

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/RestTranscriptionClient.swift`
- Create: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/RestTranscriptionClientTests.swift`

**Step 1: Write the failing test**

```swift
func testRestTranscriptionSendsMultipartRequest() async throws {
    let recorder = RequestRecorder()
    let session = URLSession(configuration: recorder.configuration)
    let client = RestTranscriptionClient(apiKey: "sk-test", session: session)

    let wavURL = FileManager.default.temporaryDirectory.appendingPathComponent("ptt.wav")
    try Data([0x00]).write(to: wavURL)

    _ = try await client.transcribe(fileURL: wavURL, model: "gpt-4o-mini-transcribe", language: "en")

    XCTAssertEqual(recorder.lastRequest?.url?.path, "/v1/audio/transcriptions")
    XCTAssertEqual(recorder.lastRequest?.httpMethod, "POST")
    XCTAssertTrue(recorder.lastBodyString?.contains("gpt-4o-mini-transcribe") == true)
    XCTAssertTrue(recorder.lastBodyString?.contains("filename=\"ptt.wav\"") == true)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter RestTranscriptionClientTests/testRestTranscriptionSendsMultipartRequest`  
Expected: FAIL

**Step 3: Write minimal implementation**

- Build multipart/form-data body with fields: `model`, optional `language`, and `file`.
- Parse JSON response `{ "text": "..." }`.

**Step 4: Run test to verify it passes**

Run: `swift test --filter RestTranscriptionClientTests/testRestTranscriptionSendsMultipartRequest`  
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/RestTranscriptionClient.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/RestTranscriptionClientTests.swift
git commit -m "feat: add rest transcription client"
```

---

### Task 4: Realtime client updates (clear + commit helpers)

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Realtime/RealtimeWebSocketClient.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/RealtimeWebSocketClientTests.swift`

**Step 1: Write the failing test**

```swift
func testClearAudioBufferEncodesEvent() async throws {
    let client = RealtimeWebSocketClient(apiKey: "sk-test")
    let payload = try JSONEncoder().encode(InputAudioBufferClearEvent())
    let text = String(data: payload, encoding: .utf8)!
    XCTAssertTrue(text.contains("\"type\":\"input_audio_buffer.clear\""))
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter RealtimeWebSocketClientTests/testClearAudioBufferEncodesEvent`  
Expected: FAIL

**Step 3: Write minimal implementation**

- Add `InputAudioBufferClearEvent` struct.
- Add `clearAudioBuffer()` method that sends it.

**Step 4: Run test to verify it passes**

Run: `swift test --filter RealtimeWebSocketClientTests/testClearAudioBufferEncodesEvent`  
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Realtime/RealtimeWebSocketClient.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/RealtimeWebSocketClientTests.swift
git commit -m "feat: add input audio buffer clear event"
```

---

### Task 5: Inject dependencies + PTT stop waits for completion

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/TranscriptionViewModelTests.swift`
- Create: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TestDoubles.swift`

**Step 1: Write the failing test**

```swift
func testStopWaitsForCompletedBeforeClosingRealtime() async {
    let realtime = TestRealtimeClient()
    let audio = TestAudioCapture()
    let rest = TestRestClient()
    let viewModel = TranscriptionViewModel(
        keychain: InMemoryKeychainStore(),
        audioCapture: audio,
        realtimeFactory: { _ in realtime },
        restClient: rest
    )

    viewModel.apiKeyInput = "sk-test"
    viewModel.start(trigger: .pushToTalk)
    audio.emit(Data([0x01, 0x02]))

    await viewModel.stopAndWait()
    XCTAssertFalse(realtime.didClose)

    realtime.emit(.inputAudioCommitted(.init(itemId: "item1", previousItemId: nil)))
    realtime.emit(.transcriptionCompleted(.init(itemId: "item1", contentIndex: 0, transcript: "Test")))

    XCTAssertTrue(realtime.didClose)
    XCTAssertEqual(viewModel.transcript, "Test")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter TranscriptionViewModelTests/testStopWaitsForCompletedBeforeClosingRealtime`  
Expected: FAIL

**Step 3: Write minimal implementation**

- Add dependency injection for audio capture, realtime client factory, REST client, and WAV writer.
- Add `start(trigger:)`/`stopAndWait()` that:
  - sets VAD off for push-to-talk
  - clears audio buffer
  - tracks `hasBufferedAudio` and `pendingItemId`
  - commits on release if buffered
  - awaits completion for `pendingItemId` before closing socket

**Step 4: Run test to verify it passes**

Run: `swift test --filter TranscriptionViewModelTests/testStopWaitsForCompletedBeforeClosingRealtime`  
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/TranscriptionViewModelTests.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Transcription/TestDoubles.swift
git commit -m "feat: keep realtime session open until transcription completes"
```

---

### Task 6: REST fallback + auto-retry once + manual retry action

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Notch/NotchRecordingController.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Notch/NotchRecordingView.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/TranscriptionViewModelTests.swift`

**Step 1: Write the failing test**

```swift
func testRealtimeFailureFallsBackToRestWithSingleRetry() async {
    let realtime = TestRealtimeClient()
    let audio = TestAudioCapture()
    let rest = TestRestClient()
    rest.queueResults([.failure(.init()), .success("Rest OK")])

    let viewModel = TranscriptionViewModel(...realtimeFactory: { _ in realtime }, restClient: rest)
    viewModel.apiKeyInput = "sk-test"
    viewModel.start(trigger: .pushToTalk)
    audio.emit(Data([0x01]))

    realtime.emit(.error("socket failed"))
    await viewModel.stopAndWait()

    XCTAssertEqual(rest.callCount, 2)
    XCTAssertEqual(viewModel.transcript, "Rest OK")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter TranscriptionViewModelTests/testRealtimeFailureFallsBackToRestWithSingleRetry`  
Expected: FAIL

**Step 3: Write minimal implementation**

- Track `realtimeFailedWhileRecording`.
- On release, if realtime failed or timed out, call REST immediately.
- If REST fails once, wait 2s and retry once, show toast.
- On second failure, keep WAV and expose manual retry action in notch.
- Always keep latest WAV only.

**Step 4: Run test to verify it passes**

Run: `swift test --filter TranscriptionViewModelTests/testRealtimeFailureFallsBackToRestWithSingleRetry`  
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift \
        Packages/FloxBoxCore/Sources/FloxBoxCore/Notch/NotchRecordingController.swift \
        Packages/FloxBoxCore/Sources/FloxBoxCore/Notch/NotchRecordingView.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/TranscriptionViewModelTests.swift
git commit -m "feat: add rest fallback and retry ui"
```

---

### Task 7: End-to-end verification

**Step 1: Run full test suite**

Run: `swift test` (from `Packages/FloxBoxCore`)  
Expected: PASS, with existing integration test skipped.

**Step 2: Commit any cleanup**

Only if needed.
