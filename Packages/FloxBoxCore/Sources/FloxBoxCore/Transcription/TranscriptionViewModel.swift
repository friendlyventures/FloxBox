import CoreAudio
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
            "Idle"
        case .connecting:
            "Connecting"
        case .recording:
            "Recording"
        case .error:
            "Error"
        }
    }
}

public enum APIKeyStatus: Equatable {
    case idle
    case saved
    case cleared
    case error(String)

    public var message: String? {
        switch self {
        case .idle:
            nil
        case .saved:
            "Saved"
        case .cleared:
            "Cleared"
        case let .error(message):
            message
        }
    }
}

@MainActor
@Observable
public final class TranscriptionViewModel {
    public var model: TranscriptionModel = .defaultModel
    public var language: TranscriptionLanguage = .defaultLanguage
    public var noiseReduction: NoiseReductionOption = .defaultOption
    public var availableInputDevices: [AudioInputDevice] = AudioInputDeviceProvider.availableDevices()
    public var selectedInputDeviceID: AudioDeviceID?
    public var vadMode: VADMode = .server
    public var manualCommitInterval: ManualCommitInterval = .defaultInterval
    public var serverVAD: ServerVADTuning = .init()
    public var semanticVAD: SemanticVADTuning = .init()

    public var apiKeyInput: String
    public var apiKeyStatus: APIKeyStatus = .idle
    public var transcript: String = ""
    public var status: RecordingStatus = .idle
    public var errorMessage: String?

    private let audioCapture = AudioCapture()
    private let transcriptStore = TranscriptStore()
    private let keychain: any KeychainStoring
    private var client: RealtimeWebSocketClient?
    private var commitTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?

    public init(keychain: any KeychainStoring = SystemKeychainStore()) {
        self.keychain = keychain
        do {
            apiKeyInput = try keychain.load() ?? ""
        } catch {
            apiKeyInput = ""
            apiKeyStatus = .error("Keychain error")
        }
    }

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

    public func refreshInputDevices() {
        availableInputDevices = AudioInputDeviceProvider.availableDevices()
    }

    public func saveAPIKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKeyInput = trimmed
        if trimmed.isEmpty {
            do {
                try keychain.delete()
                apiKeyStatus = .cleared
            } catch {
                apiKeyStatus = .error(error.localizedDescription)
            }
            return
        }

        do {
            try keychain.save(trimmed)
            apiKeyStatus = .saved
        } catch {
            apiKeyStatus = .error(error.localizedDescription)
        }
    }

    private func startInternal() async {
        guard status != .recording else { return }
        errorMessage = nil
        status = .connecting

        let apiKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            status = .error("Missing API key")
            errorMessage = "Missing API key"
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
            language: language,
            noiseReduction: noiseReduction.setting,
            vadMode: vadMode,
            serverVAD: serverVAD,
            semanticVAD: semanticVAD,
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
                await handle(event)
            }
        }

        do {
            audioCapture.setPreferredInputDevice(selectedInputDeviceID)
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
                try? await client?.commitAudio()
            }
        }
    }

    private func handle(_ event: RealtimeServerEvent) async {
        switch event {
        case let .inputAudioCommitted(committed):
            transcriptStore.applyCommitted(committed)
        case let .transcriptionDelta(delta):
            transcriptStore.applyDelta(delta)
        case let .transcriptionCompleted(completed):
            transcriptStore.applyCompleted(completed)
        case let .error(message):
            status = .error(message)
            errorMessage = message
        case .unknown:
            break
        }

        transcript = transcriptStore.displayText
    }
}
