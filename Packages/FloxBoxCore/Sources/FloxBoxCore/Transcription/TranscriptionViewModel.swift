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
    func transcribe(fileURL: URL, model: String, language: String?, prompt: String?) async throws -> String
}

@MainActor
public protocol NotchRecordingControlling: AnyObject {
    func show()
    func hide()
    func showToast(_ message: String)
    func showAction(title: String, handler: @escaping () -> Void)
    func clearToast()
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
    public var transcriptionPrompt: String = """
    You are a transcription assistant. Transcribe the spoken audio accurately.
    Preserve casing and punctuation. Do not add extra words or commentary.
    """
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
    private var recordingVADMode: VADMode = .server
    private var hasBufferedAudio = false
    private var awaitingCompletionItemId: String?
    private var shouldCloseAfterCompletion = false
    private var activeAPIKey: String?
    private var wavWriter: WavFileWriter?
    private var currentWavURL: URL?
    private var latestWavURL: URL?
    private var pendingRestWavURL: URL?
    private var realtimeFailedWhileRecording = false
    private var restRetryTask: Task<Void, Never>?
    private var restRetryDelayNanos: UInt64
    private var isRestTranscribing = false
    private var pttTailNanos: UInt64

    public init(
        keychain: any KeychainStoring = SystemKeychainStore(),
        audioCapture: any AudioCapturing = AudioCapture(),
        realtimeFactory: @escaping (String)
            -> any RealtimeTranscriptionClient = { RealtimeWebSocketClient(apiKey: $0) },
        restClient: (any RestTranscriptionClientProtocol)? = nil,
        permissionRequester: @escaping () async -> Bool = { await AudioCapture.requestPermission() },
        notchOverlay: (any NotchRecordingControlling)? = nil,
        restRetryDelayNanos: UInt64 = 2_000_000_000,
        pttTailNanos: UInt64 = 200_000_000,
    ) {
        self.keychain = keychain
        self.audioCapture = audioCapture
        self.realtimeFactory = realtimeFactory
        self.restClient = restClient
        self.permissionRequester = permissionRequester
        self.notchOverlay = notchOverlay ?? NotchRecordingController()
        self.restRetryDelayNanos = restRetryDelayNanos
        self.pttTailNanos = pttTailNanos
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

    private var normalizedPrompt: String? {
        let trimmed = transcriptionPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func start() {
        Task { await startInternal() }
    }

    func startAndWait() async {
        await startInternal()
    }

    public func stop() {
        Task { await stopInternal(waitForCompletion: true) }
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

    private func startInternal() async {
        guard status != .recording else { return }
        errorMessage = nil
        status = .connecting
        hasBufferedAudio = false
        awaitingCompletionItemId = nil
        shouldCloseAfterCompletion = false
        audioSendTask = nil
        realtimeFailedWhileRecording = false
        restRetryTask?.cancel()
        restRetryTask = nil
        isRestTranscribing = false
        pendingRestWavURL = nil
        notchOverlay.clearToast()

        let apiKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            status = .error("Missing API key")
            errorMessage = "Missing API key"
            notchOverlay.hide()
            return
        }
        activeAPIKey = apiKey

        let permitted = await permissionRequester()
        guard permitted else {
            status = .error("Microphone permission denied")
            errorMessage = "Microphone permission denied"
            notchOverlay.hide()
            return
        }

        prepareWavCapture()

        let client = realtimeFactory(apiKey)
        self.client = client
        client.connect()

        recordingVADMode = vadMode

        let config = TranscriptionSessionConfiguration(
            model: model,
            language: language,
            prompt: normalizedPrompt,
            noiseReduction: noiseReduction.setting,
            vadMode: recordingVADMode,
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

        startCommitTimerIfNeeded(vadMode: recordingVADMode)
        status = .recording
        notchOverlay.show()
    }

    private func stopInternal(waitForCompletion: Bool) async {
        guard status == .recording || status == .connecting else { return }

        notchOverlay.hide()
        commitTask?.cancel()
        commitTask = nil
        if status == .recording, pttTailNanos > 0 {
            try? await Task.sleep(nanoseconds: pttTailNanos)
        }
        audioCapture.stop()
        await Task.yield()
        finalizeWavCapture()

        let shouldAwaitCompletion = waitForCompletion

        if realtimeFailedWhileRecording {
            closeRealtime()
            await startRestFallbackIfNeeded()
            status = .idle
            return
        }

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
        status = .idle
    }

    private func startCommitTimerIfNeeded(vadMode: VADMode) {
        guard vadMode == .off, let interval = manualCommitInterval.seconds else { return }
        commitTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                try? await client?.commitAudio()
            }
        }
    }

    private func prepareWavCapture() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("floxbox-ptt-\(UUID().uuidString).wav")
        do {
            let writer = try WavFileWriter(url: url, sampleRate: 24000, channels: 1)
            wavWriter = writer
            currentWavURL = url
        } catch {
            wavWriter = nil
            currentWavURL = nil
        }
    }

    private func finalizeWavCapture() {
        guard let writer = wavWriter, let url = currentWavURL else { return }
        try? writer.finalize()
        wavWriter = nil
        currentWavURL = nil

        if hasBufferedAudio {
            pendingRestWavURL = url
            if let previous = latestWavURL, previous != url {
                try? FileManager.default.removeItem(at: previous)
            }
            latestWavURL = url
        } else {
            pendingRestWavURL = nil
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func startRestFallbackIfNeeded() async {
        guard let wavURL = pendingRestWavURL else { return }
        await performRestTranscription(wavURL: wavURL, allowRetry: true)
    }

    private func performRestTranscription(wavURL: URL, allowRetry: Bool) async {
        guard !isRestTranscribing else { return }
        guard let restClient = restClientForSession() else { return }

        isRestTranscribing = true
        defer { isRestTranscribing = false }

        do {
            let text = try await restClient.transcribe(
                fileURL: wavURL,
                model: model.rawValue,
                language: language.code,
                prompt: normalizedPrompt,
            )
            applyRestTranscription(text)
        } catch {
            if allowRetry {
                notchOverlay.showToast("Retrying...")
                restRetryTask?.cancel()
                restRetryTask = Task { [weak self] in
                    guard let self else { return }
                    try? await Task.sleep(nanoseconds: restRetryDelayNanos)
                    await performRestTranscription(wavURL: wavURL, allowRetry: false)
                }
            } else {
                showManualRetryAction(for: wavURL)
            }
        }
    }

    private func restClientForSession() -> (any RestTranscriptionClientProtocol)? {
        if let restClient {
            return restClient
        }
        guard let activeAPIKey else { return nil }
        return RestTranscriptionClient(apiKey: activeAPIKey)
    }

    private func applyRestTranscription(_ text: String) {
        transcriptStore.appendFinalText(text)
        transcript = transcriptStore.displayText
        errorMessage = nil
        realtimeFailedWhileRecording = false
        pendingRestWavURL = nil
        restRetryTask?.cancel()
        restRetryTask = nil
        notchOverlay.clearToast()
    }

    private func showManualRetryAction(for wavURL: URL) {
        notchOverlay.showToast("Transcription failed")
        notchOverlay.showAction(title: "Retry") { [weak self] in
            Task { @MainActor in
                self?.notchOverlay.showToast("Retrying...")
                await self?.performRestTranscription(wavURL: wavURL, allowRetry: false)
            }
        }
    }

    private func enqueueAudioSend(_ data: Data) {
        guard !data.isEmpty else { return }
        hasBufferedAudio = true
        wavWriter?.append(data)
        let previousTask = audioSendTask
        let client = client
        audioSendTask = Task {
            if let previousTask {
                _ = await previousTask.value
            }
            if let client {
                try? await client.sendAudio(data)
            }
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
            realtimeFailedWhileRecording = false
            if shouldCloseAfterCompletion,
               let awaitingCompletionItemId,
               awaitingCompletionItemId == completed.itemId
            {
                closeRealtime()
            }
        case let .error(message):
            errorMessage = message
            realtimeFailedWhileRecording = true
            if shouldCloseAfterCompletion {
                closeRealtime()
                await startRestFallbackIfNeeded()
            } else if status != .recording, status != .connecting {
                status = .error(message)
                notchOverlay.hide()
            }
        case .unknown:
            break
        }

        transcript = transcriptStore.displayText
    }
}
