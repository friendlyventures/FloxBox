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

public enum RecordingTrigger: Equatable {
    case manual
    case pushToTalk
}

public protocol AudioCapturing {
    func setPreferredInputDevice(_ deviceID: AudioDeviceID?)
    func start(handler: @escaping (Data) -> Void) throws
    func stop()
}

public protocol RealtimeTranscriptionClient: AnyObject {
    var events: AsyncStream<RealtimeServerEvent> { get }
    func connect()
    func sendSessionUpdate(_ update: RealtimeTranscriptionSessionUpdate) async throws
    func sendAudio(_ data: Data) async throws
    func commitAudio() async throws
    func clearAudioBuffer() async throws
    func close()
}

public protocol RestTranscriptionClientProtocol: AnyObject {
    func transcribe(fileURL: URL, model: String, language: String?) async throws -> String
}

@MainActor
public protocol NotchRecordingControlling: AnyObject {
    func show()
    func hide()
}

extension AudioCapture: AudioCapturing {}
extension RealtimeWebSocketClient: RealtimeTranscriptionClient {}
extension RestTranscriptionClient: RestTranscriptionClientProtocol {}
extension NotchRecordingController: NotchRecordingControlling {}

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

    private let audioCapture: any AudioCapturing
    private let transcriptStore = TranscriptStore()
    private let keychain: any KeychainStoring
    private let realtimeFactory: (String) -> any RealtimeTranscriptionClient
    private let restClient: (any RestTranscriptionClientProtocol)?
    private let permissionRequester: () async -> Bool
    private let notchOverlay: any NotchRecordingControlling
    private var client: (any RealtimeTranscriptionClient)?
    private var commitTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var audioSendTask: Task<Void, Never>?
    private var recordingTrigger: RecordingTrigger = .manual
    private var recordingVADMode: VADMode = .server
    private var hasBufferedAudio = false
    private var awaitingCompletionItemId: String?
    private var shouldCloseAfterCompletion = false

    public init(
        keychain: any KeychainStoring = SystemKeychainStore(),
        audioCapture: any AudioCapturing = AudioCapture(),
        realtimeFactory: @escaping (String)
            -> any RealtimeTranscriptionClient = { RealtimeWebSocketClient(apiKey: $0) },
        restClient: (any RestTranscriptionClientProtocol)? = nil,
        permissionRequester: @escaping () async -> Bool = { await AudioCapture.requestPermission() },
        notchOverlay: (any NotchRecordingControlling)? = nil,
    ) {
        self.keychain = keychain
        self.audioCapture = audioCapture
        self.realtimeFactory = realtimeFactory
        self.restClient = restClient
        self.permissionRequester = permissionRequester
        self.notchOverlay = notchOverlay ?? NotchRecordingController()
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
        start(trigger: .manual)
    }

    public func start(trigger: RecordingTrigger) {
        Task { await startInternal(trigger: trigger) }
    }

    func startAndWait(trigger: RecordingTrigger) async {
        await startInternal(trigger: trigger)
    }

    public func stop() {
        Task { await stopInternal(waitForCompletion: false) }
    }

    public func stopAndWait() async {
        await stopInternal(waitForCompletion: true)
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

    private func startInternal(trigger: RecordingTrigger) async {
        guard status != .recording else { return }
        errorMessage = nil
        status = .connecting
        recordingTrigger = trigger
        hasBufferedAudio = false
        awaitingCompletionItemId = nil
        shouldCloseAfterCompletion = false
        audioSendTask = nil

        let apiKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            status = .error("Missing API key")
            errorMessage = "Missing API key"
            notchOverlay.hide()
            return
        }

        let permitted = await permissionRequester()
        guard permitted else {
            status = .error("Microphone permission denied")
            errorMessage = "Microphone permission denied"
            notchOverlay.hide()
            return
        }

        let client = realtimeFactory(apiKey)
        self.client = client
        client.connect()

        let activeVADMode: VADMode = trigger == .pushToTalk ? .off : vadMode
        recordingVADMode = activeVADMode

        let config = TranscriptionSessionConfiguration(
            model: model,
            language: language,
            noiseReduction: noiseReduction.setting,
            vadMode: activeVADMode,
            serverVAD: serverVAD,
            semanticVAD: semanticVAD,
        )

        do {
            try await client.sendSessionUpdate(RealtimeTranscriptionSessionUpdate(configuration: config))
        } catch {
            status = .error("Failed to configure session")
            errorMessage = error.localizedDescription
            notchOverlay.hide()
            return
        }

        if trigger == .pushToTalk {
            try? await client.clearAudioBuffer()
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
                guard let self else { return }
                Task { @MainActor in
                    self.enqueueAudioSend(data)
                }
            }
        } catch {
            status = .error("Failed to start audio")
            errorMessage = error.localizedDescription
            notchOverlay.hide()
            return
        }

        startCommitTimerIfNeeded(vadMode: activeVADMode, allowInterval: trigger == .manual)
        status = .recording
        notchOverlay.show()
    }

    private func stopInternal(waitForCompletion: Bool) async {
        guard status == .recording || status == .connecting else { return }

        notchOverlay.hide()
        commitTask?.cancel()
        commitTask = nil
        audioCapture.stop()

        let shouldAwaitCompletion = waitForCompletion && recordingTrigger == .pushToTalk

        if recordingVADMode == .off {
            if hasBufferedAudio {
                if shouldAwaitCompletion {
                    shouldCloseAfterCompletion = true
                }
                if let audioSendTask {
                    _ = await audioSendTask.value
                }
                try? await client?.commitAudio()
                if !shouldAwaitCompletion {
                    closeRealtime()
                }
            } else {
                closeRealtime()
            }
        } else {
            closeRealtime()
        }
        status = .idle
    }

    private func startCommitTimerIfNeeded(vadMode: VADMode, allowInterval: Bool) {
        guard allowInterval, vadMode == .off, let interval = manualCommitInterval.seconds else { return }
        commitTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                try? await client?.commitAudio()
            }
        }
    }

    private func enqueueAudioSend(_ data: Data) {
        guard let client else { return }
        hasBufferedAudio = true
        let previousTask = audioSendTask
        audioSendTask = Task {
            if let previousTask {
                _ = await previousTask.value
            }
            try? await client.sendAudio(data)
        }
    }

    private func closeRealtime() {
        client?.close()
        client = nil
        receiveTask?.cancel()
        receiveTask = nil
        audioSendTask?.cancel()
        audioSendTask = nil
        shouldCloseAfterCompletion = false
        awaitingCompletionItemId = nil
    }

    private func handle(_ event: RealtimeServerEvent) async {
        switch event {
        case let .inputAudioCommitted(committed):
            transcriptStore.applyCommitted(committed)
            if shouldCloseAfterCompletion, awaitingCompletionItemId == nil {
                awaitingCompletionItemId = committed.itemId
            }
        case let .transcriptionDelta(delta):
            transcriptStore.applyDelta(delta)
        case let .transcriptionCompleted(completed):
            transcriptStore.applyCompleted(completed)
            if shouldCloseAfterCompletion,
               let awaitingCompletionItemId,
               awaitingCompletionItemId == completed.itemId
            {
                closeRealtime()
            }
        case let .error(message):
            status = .error(message)
            errorMessage = message
            notchOverlay.hide()
        case .unknown:
            break
        }

        transcript = transcriptStore.displayText
    }
}
