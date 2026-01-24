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
