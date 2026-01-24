# Realtime Transcription PoC Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS 14.6 SwiftUI app that streams mic audio to OpenAI Realtime transcription, with model selection, VAD modes/tuning, manual commit interval, and a live transcript view.

**Architecture:** Keep UI + orchestration in `FloxBoxCore` with a `TranscriptionViewModel` coordinating `AudioCapture`, `RealtimeWebSocketClient`, and `TranscriptStore`. The client sends `session.update`, `input_audio_buffer.append`, and `input_audio_buffer.commit` events and receives transcription delta/completed events for UI updates.

**Tech Stack:** Swift 6.2, SwiftUI, AVFoundation, URLSessionWebSocketTask, Swift Package Manager, macOS 14.6.

**Skills:** Follow @superpowers:test-driven-development for testable units and @superpowers:systematic-debugging if any test fails.

### Task 1: Add model + VAD setting types

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionModel.swift`
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/VADSettings.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/TranscriptionConfigTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import FloxBoxCore

final class TranscriptionConfigTests: XCTestCase {
    func testModelListIsExact() {
        XCTAssertEqual(
            TranscriptionModel.allCases.map(\.rawValue),
            [
                "gpt-4o-transcribe",
                "gpt-4o-transcribe-latest",
                "gpt-4o-mini-transcribe",
                "gpt-4o-mini-transcribe-2025-12-15",
                "whisper-1",
            ]
        )
    }

    func testDefaultModel() {
        XCTAssertEqual(TranscriptionModel.defaultModel, .gpt4oTranscribe)
    }

    func testManualCommitIntervalOptions() {
        XCTAssertEqual(
            ManualCommitInterval.options,
            [
                .off,
                .seconds(1),
                .seconds(2),
                .seconds(3),
                .seconds(4),
                .seconds(5),
            ]
        )
        XCTAssertEqual(ManualCommitInterval.defaultInterval, .seconds(2))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter TranscriptionConfigTests`
Expected: FAIL with missing types.

**Step 3: Write minimal implementation**

`Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionModel.swift`:

```swift
import Foundation

public enum TranscriptionModel: String, CaseIterable, Identifiable {
    case gpt4oTranscribe = "gpt-4o-transcribe"
    case gpt4oTranscribeLatest = "gpt-4o-transcribe-latest"
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"
    case gpt4oMiniTranscribe20251215 = "gpt-4o-mini-transcribe-2025-12-15"
    case whisper1 = "whisper-1"

    public static let defaultModel: TranscriptionModel = .gpt4oTranscribe

    public var id: String { rawValue }

    public var displayName: String { rawValue }
}
```

`Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/VADSettings.swift`:

```swift
import Foundation

public enum VADMode: String, CaseIterable, Identifiable {
    case off
    case server
    case semantic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .server:
            return "Server VAD"
        case .semantic:
            return "Semantic VAD"
        }
    }
}

public enum ManualCommitInterval: Equatable, CaseIterable, Identifiable {
    case off
    case seconds(Int)

    public static let options: [ManualCommitInterval] = [
        .off,
        .seconds(1),
        .seconds(2),
        .seconds(3),
        .seconds(4),
        .seconds(5),
    ]

    public static let defaultInterval: ManualCommitInterval = .seconds(2)

    public var id: String { label }

    public var label: String {
        switch self {
        case .off:
            return "Off"
        case .seconds(let value):
            return "\(value)s"
        }
    }

    public var seconds: Int? {
        switch self {
        case .off:
            return nil
        case .seconds(let value):
            return value
        }
    }
}

public struct ServerVADTuning: Equatable {
    public var threshold: Double?
    public var prefixPaddingMs: Int?
    public var silenceDurationMs: Int?
    public var idleTimeoutMs: Int?

    public init(
        threshold: Double? = nil,
        prefixPaddingMs: Int? = nil,
        silenceDurationMs: Int? = nil,
        idleTimeoutMs: Int? = nil
    ) {
        self.threshold = threshold
        self.prefixPaddingMs = prefixPaddingMs
        self.silenceDurationMs = silenceDurationMs
        self.idleTimeoutMs = idleTimeoutMs
    }
}

public enum SemanticVADEagerness: String, CaseIterable, Identifiable {
    case low
    case medium
    case high
    case auto

    public var id: String { rawValue }

    public var displayName: String { rawValue }
}

public struct SemanticVADTuning: Equatable {
    public var eagerness: SemanticVADEagerness?

    public init(eagerness: SemanticVADEagerness? = nil) {
        self.eagerness = eagerness
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/FloxBoxCore --filter TranscriptionConfigTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionModel.swift \
        Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/VADSettings.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/TranscriptionConfigTests.swift
git commit -m "feat: add transcription model and VAD settings"
```

### Task 2: Encode session.update payload (including VAD off as null)

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Realtime/SessionUpdatePayload.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/SessionUpdatePayloadTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import FloxBoxCore

final class SessionUpdatePayloadTests: XCTestCase {
    func testTurnDetectionDisabledEncodesNull() throws {
        let config = TranscriptionSessionConfiguration(
            model: .gpt4oTranscribe,
            vadMode: .off,
            serverVAD: .init(),
            semanticVAD: .init()
        )
        let update = RealtimeTranscriptionSessionUpdate(configuration: config)
        let data = try JSONEncoder().encode(update)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let turnDetection = (((json?["session"] as? [String: Any])?["audio"] as? [String: Any])?["input"] as? [String: Any])?["turn_detection"]
        XCTAssertTrue(turnDetection is NSNull)
    }

    func testServerVADEncodesOverrides() throws {
        let config = TranscriptionSessionConfiguration(
            model: .gpt4oTranscribe,
            vadMode: .server,
            serverVAD: .init(threshold: 0.2, prefixPaddingMs: 150, silenceDurationMs: 900, idleTimeoutMs: 5000),
            semanticVAD: .init()
        )
        let update = RealtimeTranscriptionSessionUpdate(configuration: config)
        let data = try JSONEncoder().encode(update)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let input = ((json?["session"] as? [String: Any])?["audio"] as? [String: Any])?["input"] as? [String: Any]
        let turnDetection = input?["turn_detection"] as? [String: Any]
        XCTAssertEqual(turnDetection?["type"] as? String, "server_vad")
        XCTAssertEqual(turnDetection?["threshold"] as? Double, 0.2)
        XCTAssertEqual(turnDetection?["prefix_padding_ms"] as? Int, 150)
        XCTAssertEqual(turnDetection?["silence_duration_ms"] as? Int, 900)
        XCTAssertEqual(turnDetection?["idle_timeout_ms"] as? Int, 5000)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter SessionUpdatePayloadTests`
Expected: FAIL with missing types.

**Step 3: Write minimal implementation**

`Packages/FloxBoxCore/Sources/FloxBoxCore/Realtime/SessionUpdatePayload.swift`:

```swift
import Foundation

public struct TranscriptionSessionConfiguration: Equatable {
    public var model: TranscriptionModel
    public var vadMode: VADMode
    public var serverVAD: ServerVADTuning
    public var semanticVAD: SemanticVADTuning

    public init(
        model: TranscriptionModel,
        vadMode: VADMode,
        serverVAD: ServerVADTuning,
        semanticVAD: SemanticVADTuning
    ) {
        self.model = model
        self.vadMode = vadMode
        self.serverVAD = serverVAD
        self.semanticVAD = semanticVAD
    }

    public var turnDetectionSetting: TurnDetectionSetting {
        switch vadMode {
        case .off:
            return .disabled
        case .server:
            return .server(serverVAD)
        case .semantic:
            return .semantic(semanticVAD)
        }
    }
}

public struct RealtimeTranscriptionSessionUpdate: Encodable, Equatable {
    public let type: String = "session.update"
    public let session: Session

    public init(configuration: TranscriptionSessionConfiguration) {
        self.session = Session(
            audio: Audio(
                input: Input(
                    format: Format(type: "audio/pcm", rate: 24_000),
                    transcription: Transcription(model: configuration.model.rawValue),
                    turnDetection: configuration.turnDetectionSetting
                )
            ),
            include: ["item.input_audio_transcription.logprobs"]
        )
    }

    public struct Session: Encodable, Equatable {
        public let audio: Audio
        public let include: [String]?
    }

    public struct Audio: Encodable, Equatable {
        public let input: Input
    }

    public struct Input: Encodable, Equatable {
        public let format: Format
        public let transcription: Transcription
        public let turnDetection: TurnDetectionSetting

        enum CodingKeys: String, CodingKey {
            case format
            case transcription
            case turnDetection = "turn_detection"
        }
    }

    public struct Format: Encodable, Equatable {
        public let type: String
        public let rate: Int
    }

    public struct Transcription: Encodable, Equatable {
        public let model: String
    }
}

public enum TurnDetectionSetting: Encodable, Equatable {
    case disabled
    case server(ServerVADTuning)
    case semantic(SemanticVADTuning)

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .disabled:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .server(let tuning):
            try TurnDetectionPayload(
                type: "server_vad",
                threshold: tuning.threshold,
                prefixPaddingMs: tuning.prefixPaddingMs,
                silenceDurationMs: tuning.silenceDurationMs,
                idleTimeoutMs: tuning.idleTimeoutMs,
                eagerness: nil
            ).encode(to: encoder)
        case .semantic(let tuning):
            try TurnDetectionPayload(
                type: "semantic_vad",
                threshold: nil,
                prefixPaddingMs: nil,
                silenceDurationMs: nil,
                idleTimeoutMs: nil,
                eagerness: tuning.eagerness?.rawValue
            ).encode(to: encoder)
        }
    }
}

public struct TurnDetectionPayload: Encodable, Equatable {
    public let type: String
    public let threshold: Double?
    public let prefixPaddingMs: Int?
    public let silenceDurationMs: Int?
    public let idleTimeoutMs: Int?
    public let eagerness: String?

    enum CodingKeys: String, CodingKey {
        case type
        case threshold
        case prefixPaddingMs = "prefix_padding_ms"
        case silenceDurationMs = "silence_duration_ms"
        case idleTimeoutMs = "idle_timeout_ms"
        case eagerness
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/FloxBoxCore --filter SessionUpdatePayloadTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Realtime/SessionUpdatePayload.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/SessionUpdatePayloadTests.swift
git commit -m "feat: add session update payload encoding"
```

### Task 3: Decode realtime events + transcript store

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Realtime/RealtimeEvents.swift`
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptStore.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/TranscriptStoreTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import FloxBoxCore

final class TranscriptStoreTests: XCTestCase {
    func testOutOfOrderCompletionsUseCommitOrder() {
        let store = TranscriptStore()
        store.applyCommitted(.init(itemId: "item-1", previousItemId: nil))
        store.applyCommitted(.init(itemId: "item-2", previousItemId: "item-1"))

        store.applyCompleted(.init(itemId: "item-2", contentIndex: 0, transcript: "Second"))
        store.applyCompleted(.init(itemId: "item-1", contentIndex: 0, transcript: "First"))

        XCTAssertEqual(store.displayText, "First\nSecond")
    }

    func testDeltaThenCompletionReplacesText() {
        let store = TranscriptStore()
        store.applyCommitted(.init(itemId: "item-1", previousItemId: nil))
        store.applyDelta(.init(itemId: "item-1", contentIndex: 0, delta: "Hel"))
        store.applyDelta(.init(itemId: "item-1", contentIndex: 0, delta: "lo"))
        XCTAssertEqual(store.displayText, "Hello")

        store.applyCompleted(.init(itemId: "item-1", contentIndex: 0, transcript: "Hello there"))
        XCTAssertEqual(store.displayText, "Hello there")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter TranscriptStoreTests`
Expected: FAIL with missing types.

**Step 3: Write minimal implementation**

`Packages/FloxBoxCore/Sources/FloxBoxCore/Realtime/RealtimeEvents.swift`:

```swift
import Foundation

public enum RealtimeServerEvent: Equatable {
    case transcriptionDelta(TranscriptionDeltaEvent)
    case transcriptionCompleted(TranscriptionCompletedEvent)
    case inputAudioCommitted(InputAudioCommittedEvent)
    case error(String)
    case unknown(String)
}

public struct TranscriptionDeltaEvent: Decodable, Equatable {
    public let itemId: String
    public let contentIndex: Int
    public let delta: String

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case contentIndex = "content_index"
        case delta
    }
}

public struct TranscriptionCompletedEvent: Decodable, Equatable {
    public let itemId: String
    public let contentIndex: Int
    public let transcript: String

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case contentIndex = "content_index"
        case transcript
    }
}

public struct InputAudioCommittedEvent: Decodable, Equatable {
    public let itemId: String
    public let previousItemId: String?

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case previousItemId = "previous_item_id"
    }
}

public struct RealtimeErrorEvent: Decodable, Equatable {
    public struct ErrorDetail: Decodable, Equatable {
        public let message: String
    }

    public let error: ErrorDetail
}

private struct RealtimeEventEnvelope: Decodable {
    let type: String
}

public enum RealtimeEventDecoder {
    public static func decode(_ data: Data) throws -> RealtimeServerEvent {
        let envelope = try JSONDecoder().decode(RealtimeEventEnvelope.self, from: data)
        switch envelope.type {
        case "conversation.item.input_audio_transcription.delta":
            return .transcriptionDelta(try JSONDecoder().decode(TranscriptionDeltaEvent.self, from: data))
        case "conversation.item.input_audio_transcription.completed":
            return .transcriptionCompleted(try JSONDecoder().decode(TranscriptionCompletedEvent.self, from: data))
        case "input_audio_buffer.committed":
            return .inputAudioCommitted(try JSONDecoder().decode(InputAudioCommittedEvent.self, from: data))
        case "error":
            let error = try JSONDecoder().decode(RealtimeErrorEvent.self, from: data)
            return .error(error.error.message)
        default:
            return .unknown(envelope.type)
        }
    }
}
```

`Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptStore.swift`:

```swift
import Foundation

public struct TranscriptSegment: Equatable, Identifiable {
    public let id: String
    public var text: String
    public var isFinal: Bool
}

public final class TranscriptStore {
    private var order: [String] = []
    private var segments: [String: TranscriptSegment] = [:]

    public init() {}

    public func reset() {
        order.removeAll()
        segments.removeAll()
    }

    public func applyCommitted(_ event: InputAudioCommittedEvent) {
        guard !order.contains(event.itemId) else { return }
        if let previousId = event.previousItemId, let index = order.firstIndex(of: previousId) {
            order.insert(event.itemId, at: index + 1)
        } else if event.previousItemId == nil {
            order.insert(event.itemId, at: 0)
        } else {
            order.append(event.itemId)
        }
    }

    public func applyDelta(_ event: TranscriptionDeltaEvent) {
        var segment = segments[event.itemId] ?? TranscriptSegment(id: event.itemId, text: "", isFinal: false)
        if !segment.isFinal {
            segment.text += event.delta
        }
        segments[event.itemId] = segment
        if !order.contains(event.itemId) {
            order.append(event.itemId)
        }
    }

    public func applyCompleted(_ event: TranscriptionCompletedEvent) {
        segments[event.itemId] = TranscriptSegment(id: event.itemId, text: event.transcript, isFinal: true)
        if !order.contains(event.itemId) {
            order.append(event.itemId)
        }
    }

    public var displayText: String {
        order.compactMap { segments[$0]?.text }.joined(separator: "\n")
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/FloxBoxCore --filter TranscriptStoreTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Realtime/RealtimeEvents.swift \
        Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptStore.swift \
        Packages/FloxBoxCore/Tests/FloxBoxCoreTests/TranscriptStoreTests.swift
git commit -m "feat: add realtime events and transcript store"
```

### Task 4: Capture mic audio and convert to PCM16 24 kHz mono

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Audio/AudioCapture.swift`

**Step 1: Write the failing test**

_No unit test for AVAudioEngine capture. Proceed with a compile check._

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter TranscriptStoreTests`
Expected: PASS (baseline)

**Step 3: Write minimal implementation**

`Packages/FloxBoxCore/Sources/FloxBoxCore/Audio/AudioCapture.swift`:

```swift
import AVFoundation

public final class AudioCapture {
    public typealias Handler = @Sendable (Data) -> Void

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var isRunning = false

    public init() {}

    public static func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    public func start(handler: @escaping Handler) throws {
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24_000,
            channels: 1,
            interleaved: true
        )!

        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.converter else { return }

            let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: AVAudioFrameCount(1024)
            )
            guard let convertedBuffer else { return }

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
            guard error == nil else { return }

            handler(convertedBuffer.pcm16Data())
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }
}

private extension AVAudioPCMBuffer {
    func pcm16Data() -> Data {
        guard let channel = int16ChannelData else { return Data() }
        let frames = Int(frameLength)
        return Data(bytes: channel[0], count: frames * MemoryLayout<Int16>.size)
    }
}
```

**Step 4: Run tests to ensure no regression**

Run: `swift test --package-path Packages/FloxBoxCore`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Audio/AudioCapture.swift
git commit -m "feat: add audio capture and PCM conversion"
```

### Task 5: Add realtime WebSocket client

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Realtime/RealtimeWebSocketClient.swift`

**Step 1: Write the failing test**

_No unit test for URLSessionWebSocketTask. Proceed with compile check._

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter TranscriptStoreTests`
Expected: PASS (baseline)

**Step 3: Write minimal implementation**

`Packages/FloxBoxCore/Sources/FloxBoxCore/Realtime/RealtimeWebSocketClient.swift`:

```swift
import Foundation

public enum RealtimeAPI {
    public static let baseURL = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-realtime")!
}

public struct InputAudioBufferAppendEvent: Encodable {
    public let type: String = "input_audio_buffer.append"
    public let audio: String
}

public struct InputAudioBufferCommitEvent: Encodable {
    public let type: String = "input_audio_buffer.commit"
}

public final class RealtimeWebSocketClient {
    private let apiKey: String
    private let urlSession: URLSession
    private var socket: URLSessionWebSocketTask?

    private let stream: AsyncStream<RealtimeServerEvent>
    private let continuation: AsyncStream<RealtimeServerEvent>.Continuation

    public init(apiKey: String, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.urlSession = urlSession
        var continuation: AsyncStream<RealtimeServerEvent>.Continuation!
        self.stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    public var events: AsyncStream<RealtimeServerEvent> {
        stream
    }

    public func connect() {
        var request = URLRequest(url: RealtimeAPI.baseURL)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let socket = urlSession.webSocketTask(with: request)
        self.socket = socket
        socket.resume()
        receiveLoop()
    }

    public func sendSessionUpdate(_ update: RealtimeTranscriptionSessionUpdate) async throws {
        try await send(update)
    }

    public func sendAudio(_ data: Data) async throws {
        try await send(InputAudioBufferAppendEvent(audio: data.base64EncodedString()))
    }

    public func commitAudio() async throws {
        try await send(InputAudioBufferCommitEvent())
    }

    public func close() {
        socket?.cancel(with: .goingAway, reason: nil)
        continuation.finish()
    }

    private func send<Event: Encodable>(_ event: Event) async throws {
        guard let socket else { return }
        let payload = try JSONEncoder().encode(event)
        try await socket.send(.data(payload))
    }

    private func receiveLoop() {
        guard let socket else { return }
        Task.detached { [weak self] in
            while true {
                do {
                    let message = try await socket.receive()
                    let data: Data
                    switch message {
                    case .data(let payload):
                        data = payload
                    case .string(let text):
                        data = Data(text.utf8)
                    @unknown default:
                        continue
                    }

                    if let event = try? RealtimeEventDecoder.decode(data) {
                        self?.continuation.yield(event)
                    }
                } catch {
                    self?.continuation.yield(.error(error.localizedDescription))
                    break
                }
            }
        }
    }
}
```

**Step 4: Run tests to ensure no regression**

Run: `swift test --package-path Packages/FloxBoxCore`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Realtime/RealtimeWebSocketClient.swift
git commit -m "feat: add realtime websocket client"
```

### Task 6: Add transcription view model

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift`

**Step 1: Write the failing test**

_No unit tests for the async view model in the PoC. Proceed with compile check._

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter TranscriptStoreTests`
Expected: PASS (baseline)

**Step 3: Write minimal implementation**

`Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift`:

```swift
import Foundation
import Observation

public enum RecordingStatus: Equatable {
    case idle
    case connecting
    case recording
    case error(String)

    public var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .connecting:
            return "Connecting"
        case .recording:
            return "Recording"
        case .error:
            return "Error"
        }
    }
}

@MainActor
@Observable
public final class TranscriptionViewModel {
    public var model: TranscriptionModel = .defaultModel
    public var vadMode: VADMode = .server
    public var manualCommitInterval: ManualCommitInterval = .defaultInterval
    public var serverVAD: ServerVADTuning = .init()
    public var semanticVAD: SemanticVADTuning = .init()

    public var transcript: String = ""
    public var status: RecordingStatus = .idle
    public var errorMessage: String?

    private let audioCapture = AudioCapture()
    private let transcriptStore = TranscriptStore()
    private var client: RealtimeWebSocketClient?
    private var commitTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?

    public init() {}

    public var isRecording: Bool {
        status == .recording
    }

    public func start() {
        Task { await startInternal() }
    }

    public func stop() {
        Task { await stopInternal() }
    }

    public func clearTranscript() {
        transcriptStore.reset()
        transcript = ""
    }

    private func startInternal() async {
        guard status != .recording else { return }
        errorMessage = nil
        status = .connecting

        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty else {
            status = .error("Missing OPENAI_API_KEY")
            errorMessage = "Missing OPENAI_API_KEY"
            return
        }

        let permitted = await AudioCapture.requestPermission()
        guard permitted else {
            status = .error("Microphone permission denied")
            errorMessage = "Microphone permission denied"
            return
        }

        let client = RealtimeWebSocketClient(apiKey: apiKey)
        self.client = client
        client.connect()

        let config = TranscriptionSessionConfiguration(
            model: model,
            vadMode: vadMode,
            serverVAD: serverVAD,
            semanticVAD: semanticVAD
        )

        do {
            try await client.sendSessionUpdate(RealtimeTranscriptionSessionUpdate(configuration: config))
        } catch {
            status = .error("Failed to configure session")
            errorMessage = error.localizedDescription
            return
        }

        receiveTask = Task { [weak self] in
            guard let self else { return }
            for await event in client.events {
                await self.handle(event)
            }
        }

        do {
            try audioCapture.start { [weak self] data in
                guard let self, let client = self.client else { return }
                Task {
                    try? await client.sendAudio(data)
                }
            }
        } catch {
            status = .error("Failed to start audio")
            errorMessage = error.localizedDescription
            return
        }

        startCommitTimerIfNeeded()
        status = .recording
    }

    private func stopInternal() async {
        guard status == .recording || status == .connecting else { return }

        commitTask?.cancel()
        commitTask = nil
        audioCapture.stop()

        if vadMode == .off {
            try? await client?.commitAudio()
        }

        client?.close()
        client = nil
        receiveTask?.cancel()
        receiveTask = nil
        status = .idle
    }

    private func startCommitTimerIfNeeded() {
        guard vadMode == .off, let interval = manualCommitInterval.seconds else { return }
        commitTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                try? await self.client?.commitAudio()
            }
        }
    }

    private func handle(_ event: RealtimeServerEvent) async {
        switch event {
        case .inputAudioCommitted(let committed):
            transcriptStore.applyCommitted(committed)
        case .transcriptionDelta(let delta):
            transcriptStore.applyDelta(delta)
        case .transcriptionCompleted(let completed):
            transcriptStore.applyCompleted(completed)
        case .error(let message):
            status = .error(message)
            errorMessage = message
        case .unknown:
            break
        }

        transcript = transcriptStore.displayText
    }
}
```

**Step 4: Run tests to ensure no regression**

Run: `swift test --package-path Packages/FloxBoxCore`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Transcription/TranscriptionViewModel.swift
git commit -m "feat: add transcription view model"
```

### Task 7: Update the SwiftUI UI

**Files:**
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Views/ContentView.swift`

**Step 1: Write the failing test**

_No unit test for SwiftUI view. Proceed with compile check._

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore --filter TranscriptStoreTests`
Expected: PASS (baseline)

**Step 3: Write minimal implementation**

`Packages/FloxBoxCore/Sources/FloxBoxCore/Views/ContentView.swift`:

```swift
import SwiftUI
import Observation

public struct ContentView: View {
    private let configuration: FloxBoxDistributionConfiguration
    @State private var viewModel = TranscriptionViewModel()

    public init(configuration: FloxBoxDistributionConfiguration) {
        self.configuration = configuration
    }

    public var body: some View {
        @Bindable var viewModel = viewModel

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Picker("Model", selection: $viewModel.model) {
                    ForEach(TranscriptionModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .frame(minWidth: 240)

                Picker("VAD Mode", selection: $viewModel.vadMode) {
                    ForEach(VADMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
            }

            if viewModel.vadMode == .off {
                Picker("Commit Interval", selection: $viewModel.manualCommitInterval) {
                    ForEach(ManualCommitInterval.options) { option in
                        Text(option.label).tag(option)
                    }
                }
                .frame(maxWidth: 240)
            }

            if viewModel.vadMode == .server {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Server VAD Tuning")
                        .font(.headline)

                    HStack(spacing: 12) {
                        OptionalDoubleField(title: "Threshold", value: $viewModel.serverVAD.threshold)
                        OptionalIntField(title: "Prefix Padding (ms)", value: $viewModel.serverVAD.prefixPaddingMs)
                        OptionalIntField(title: "Silence Duration (ms)", value: $viewModel.serverVAD.silenceDurationMs)
                        OptionalIntField(title: "Idle Timeout (ms)", value: $viewModel.serverVAD.idleTimeoutMs)
                    }
                }
            }

            HStack(spacing: 12) {
                Button(viewModel.isRecording ? "Stop" : "Start") {
                    viewModel.isRecording ? viewModel.stop() : viewModel.start()
                }
                .buttonStyle(.borderedProminent)

                Button("Clear") {
                    viewModel.clearTranscript()
                }

                Spacer()

                Text(viewModel.status.label)
                    .foregroundStyle(viewModel.status == .error("") ? .red : .secondary)
            }

            TextEditor(text: $viewModel.transcript)
                .font(.body)
                .frame(minHeight: 320)

            Text(configuration.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(minWidth: 900, minHeight: 600)
    }
}

private struct OptionalDoubleField: View {
    let title: String
    @Binding var value: Double?
    @State private var text: String

    init(title: String, value: Binding<Double?>) {
        self.title = title
        self._value = value
        self._text = State(initialValue: value.wrappedValue.map(String.init) ?? "")
    }

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.roundedBorder)
            .onChange(of: text) { _, newValue in
                value = Double(newValue)
            }
    }
}

private struct OptionalIntField: View {
    let title: String
    @Binding var value: Int?
    @State private var text: String

    init(title: String, value: Binding<Int?>) {
        self.title = title
        self._value = value
        self._text = State(initialValue: value.wrappedValue.map(String.init) ?? "")
    }

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.roundedBorder)
            .onChange(of: text) { _, newValue in
                value = Int(newValue)
            }
    }
}
```

**Step 4: Run tests to ensure no regression**

Run: `swift test --package-path Packages/FloxBoxCore`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Views/ContentView.swift
git commit -m "feat: build realtime transcription UI"
```

### Task 8: Update project settings, entitlements, and deployment targets

**Files:**
- Modify: `FloxBox.xcodeproj/project.pbxproj`
- Modify: `FloxBox/FloxBox.entitlements`
- Modify: `FloxBox/FloxBoxAppStore.entitlements`
- Modify: `Packages/FloxBoxCore/Package.swift`

**Step 1: Write the failing test**

_No unit tests for project settings. Proceed with settings updates and a build smoke test._

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/FloxBoxCore`
Expected: PASS (baseline)

**Step 3: Write minimal implementation**

1) Update deployment target and Swift version in `FloxBox.xcodeproj/project.pbxproj`:
- Replace all `MACOSX_DEPLOYMENT_TARGET = 26.2;` with `MACOSX_DEPLOYMENT_TARGET = 14.6;`
- Replace all `SWIFT_VERSION = 5.0;` with `SWIFT_VERSION = 6.2;`
- Add `INFOPLIST_KEY_NSMicrophoneUsageDescription = "FloxBox records audio to transcribe your speech.";` to each app target build configuration (Debug/Release for both direct and App Store targets).

2) Update entitlements to allow mic + network:

`FloxBox/FloxBox.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

`FloxBox/FloxBoxAppStore.entitlements` (add audio input):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
```

3) Update `Packages/FloxBoxCore/Package.swift` platforms:

```swift
platforms: [.macOS(.v14_6)],
```

**Step 4: Run tests/build to ensure no regression**

Run: `swift test --package-path Packages/FloxBoxCore`
Expected: PASS

**Step 5: Commit**

```bash
git add FloxBox.xcodeproj/project.pbxproj \
        FloxBox/FloxBox.entitlements \
        FloxBox/FloxBoxAppStore.entitlements \
        Packages/FloxBoxCore/Package.swift
git commit -m "chore: target macOS 14.6 and add mic permissions"
```
