import AppKit
import Carbon
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
    private let accessibilityChecker: () -> Bool
    private let secureInputChecker: () -> Bool
    private let permissionsPresenter: () -> Void
    private let dictationInjector: any DictationInjectionControlling
    private let clipboardWriter: (String) -> Void
    private let notchOverlay: any NotchRecordingControlling
    private let toastPresenter: any ToastPresenting
    private var client: (any RealtimeTranscriptionClient)?
    private var commitTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var audioSendTask: Task<Void, Never>?
    private var recordingVADMode: VADMode = .server
    private var hasBufferedAudio = false
    private var isRealtimeReady = false
    private var pendingAudio: [Data] = []
    private var sessionUpdateTask: Task<Void, Error>?
    private var recordingSessionID: String?
    private var audioBufferCount = 0
    private var firstAudioUptime: TimeInterval?
    private var lastAudioUptime: TimeInterval?
    private var sendCount = 0
    private var firstSendUptime: TimeInterval?
    private var actualSendCount = 0
    private var firstSendActualUptime: TimeInterval?
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
    private var didFinishInjection = false

    public init(
        keychain: any KeychainStoring = SystemKeychainStore(),
        audioCapture: any AudioCapturing = AudioCapture(),
        realtimeFactory: @escaping (String)
            -> any RealtimeTranscriptionClient = { RealtimeWebSocketClient(apiKey: $0) },
        restClient: (any RestTranscriptionClientProtocol)? = nil,
        permissionRequester: @escaping () async -> Bool = { await AudioCapture.requestPermission() },
        notchOverlay: (any NotchRecordingControlling)? = nil,
        toastPresenter: (any ToastPresenting)? = nil,
        restRetryDelayNanos: UInt64 = 2_000_000_000,
        pttTailNanos: UInt64 = 200_000_000,
        accessibilityChecker: @escaping () -> Bool = { AccessibilityPermissionClient().isTrusted() },
        secureInputChecker: @escaping () -> Bool = { IsSecureEventInputEnabled() },
        permissionsPresenter: @escaping () -> Void = {},
        dictationInjector: (any DictationInjectionControlling)? = nil,
        clipboardWriter: @escaping (String) -> Void = { text in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        },
    ) {
        self.keychain = keychain
        self.audioCapture = audioCapture
        self.realtimeFactory = realtimeFactory
        self.restClient = restClient
        self.permissionRequester = permissionRequester
        self.accessibilityChecker = accessibilityChecker
        self.secureInputChecker = secureInputChecker
        self.permissionsPresenter = permissionsPresenter
        self.dictationInjector = dictationInjector ?? DictationInjectionController()
        self.clipboardWriter = clipboardWriter
        self.notchOverlay = notchOverlay ?? NotchRecordingController()
        self.toastPresenter = toastPresenter ?? SystemNotificationPresenter()
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
        let sessionID = String(UUID().uuidString.prefix(8))
        recordingSessionID = sessionID
        resetRecordingState(sessionID: sessionID)

        guard let apiKey = await validateStart(sessionID: sessionID) else { return }

        beginDictationSession()
        let client = startRealtimeClient(apiKey: apiKey, sessionID: sessionID)
        guard startAudioCapture(sessionID: sessionID) else { return }

        status = .recording
        DebugLog.recording(logStatusChange("status.recording", sessionID: sessionID))
        notchOverlay.show()

        let config = TranscriptionSessionConfiguration(
            model: model,
            language: language,
            prompt: normalizedPrompt,
            noiseReduction: noiseReduction.setting,
            vadMode: recordingVADMode,
            serverVAD: serverVAD,
            semanticVAD: semanticVAD,
        )

        await performSessionUpdate(client: client, config: config, sessionID: sessionID)
    }

    private func resetRecordingState(sessionID: String) {
        audioBufferCount = 0
        firstAudioUptime = nil
        lastAudioUptime = nil
        sendCount = 0
        firstSendUptime = nil
        actualSendCount = 0
        firstSendActualUptime = nil

        DebugLog.recording(logStatusChange("record.start", sessionID: sessionID))
        errorMessage = nil
        status = .connecting
        DebugLog.recording(logStatusChange("status.connecting", sessionID: sessionID))
        hasBufferedAudio = false
        isRealtimeReady = false
        pendingAudio.removeAll()
        sessionUpdateTask?.cancel()
        sessionUpdateTask = nil
        awaitingCompletionItemId = nil
        shouldCloseAfterCompletion = false
        audioSendTask = nil
        realtimeFailedWhileRecording = false
        restRetryTask?.cancel()
        restRetryTask = nil
        isRestTranscribing = false
        pendingRestWavURL = nil
        didFinishInjection = false
        toastPresenter.clearToast()
    }

    private func validateStart(sessionID: String) async -> String? {
        let apiKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            status = .error("Missing API key")
            errorMessage = "Missing API key"
            notchOverlay.hide()
            ShortcutDebugLogger.log("dictation.start blocked missingApiKey")
            DebugLog.recording(logStatusChange("error.missing_api_key", sessionID: sessionID))
            return nil
        }
        activeAPIKey = apiKey

        guard accessibilityChecker() else {
            status = .idle
            toastPresenter.showToast("Accessibility permission required")
            permissionsPresenter()
            ShortcutDebugLogger.log("dictation.start blocked accessibility")
            DebugLog.recording(logStatusChange("error.accessibility_denied", sessionID: sessionID))
            return nil
        }

        if secureInputChecker() {
            status = .idle
            toastPresenter.showToast("Secure input active")
            ShortcutDebugLogger.log("dictation.start blocked secureInput")
            DebugLog.recording(logStatusChange("error.secure_input", sessionID: sessionID))
            return nil
        }

        let permitted = await permissionRequester()
        guard permitted else {
            status = .error("Microphone permission denied")
            errorMessage = "Microphone permission denied"
            notchOverlay.hide()
            ShortcutDebugLogger.log("dictation.start blocked microphoneDenied")
            DebugLog.recording(logStatusChange("error.permission_denied", sessionID: sessionID))
            return nil
        }

        return apiKey
    }

    private func beginDictationSession() {
        transcriptStore.reset()
        transcript = ""
        ShortcutDebugLogger.log("dictation.start transcriptReset")
        dictationInjector.startSession()
        ShortcutDebugLogger.log("dictation.start sessionBegin")
        prepareWavCapture()
    }

    private func startRealtimeClient(apiKey: String, sessionID: String) -> any RealtimeTranscriptionClient {
        let client = realtimeFactory(apiKey)
        self.client = client
        client.connect()
        DebugLog.recording(logStatusChange("realtime.connect_called", sessionID: sessionID))

        receiveTask = Task { [weak self] in
            guard let self else { return }
            for await event in client.events {
                await handle(event)
            }
        }

        recordingVADMode = vadMode
        return client
    }

    private func startAudioCapture(sessionID: String) -> Bool {
        do {
            audioCapture.setPreferredInputDevice(selectedInputDeviceID)
            DebugLog.recording(logStatusChange("audio.starting", sessionID: sessionID))
            try audioCapture.start { [weak self] data in
                guard let self else { return }
                Task { @MainActor in
                    self.enqueueAudioSend(data)
                }
            }
            DebugLog.recording(logStatusChange("audio.started", sessionID: sessionID))
            return true
        } catch {
            status = .error("Failed to start audio")
            errorMessage = error.localizedDescription
            notchOverlay.hide()
            let errorLog = [
                "audio.start.error",
                "session=\(sessionID)",
                "uptime=\(ProcessInfo.processInfo.systemUptime)",
                "error=\(error.localizedDescription)",
            ].joined(separator: " ")
            DebugLog.recording(errorLog)
            return false
        }
    }

    private func performSessionUpdate(
        client: any RealtimeTranscriptionClient,
        config: TranscriptionSessionConfiguration,
        sessionID: String,
    ) async {
        DebugLog.recording(logStatusChange("realtime.session_update.start", sessionID: sessionID))
        sessionUpdateTask = Task {
            try await client.sendSessionUpdate(RealtimeTranscriptionSessionUpdate(configuration: config))
        }

        do {
            try await sessionUpdateTask?.value
            DebugLog.recording(logStatusChange("realtime.session_update.ok", sessionID: sessionID))
            markRealtimeReady(startCommitTimer: true)
        } catch {
            realtimeFailedWhileRecording = true
            errorMessage = error.localizedDescription
            let errorLog = [
                "realtime.session_update.error",
                "session=\(sessionID)",
                "uptime=\(ProcessInfo.processInfo.systemUptime)",
                "error=\(error.localizedDescription)",
            ].joined(separator: " ")
            DebugLog.recording(errorLog)
            closeRealtime()
        }
    }

    private func logStatusChange(_ prefix: String, sessionID: String) -> String {
        "\(prefix) session=\(sessionID) uptime=\(ProcessInfo.processInfo.systemUptime)"
    }

    private func stopInternal(waitForCompletion: Bool) async {
        guard status == .recording || status == .connecting else { return }
        let sessionID = recordingSessionID ?? "unknown"
        let stopLog = [
            "record.stop.start",
            "session=\(sessionID)",
            "status=\(status)",
            "uptime=\(ProcessInfo.processInfo.systemUptime)",
        ].joined(separator: " ")
        DebugLog.recording(stopLog)

        notchOverlay.hide()
        commitTask?.cancel()
        commitTask = nil
        if status == .recording, pttTailNanos > 0 {
            try? await Task.sleep(nanoseconds: pttTailNanos)
            let tailLog = [
                "ptt.tail.complete",
                "session=\(sessionID)",
                "tailNanos=\(pttTailNanos)",
                "uptime=\(ProcessInfo.processInfo.systemUptime)",
            ].joined(separator: " ")
            DebugLog.recording(tailLog)
        }
        audioCapture.stop()
        await Task.yield()
        finalizeWavCapture()
        let firstSendQueued = firstSendUptime.map { String(describing: $0) } ?? "nil"
        let firstSendActual = firstSendActualUptime.map { String(describing: $0) } ?? "nil"
        let baseSummary = [
            "audio.summary",
            "session=\(sessionID)",
            "buffers=\(audioBufferCount)",
        ]
        if let firstAudioUptime, let lastAudioUptime {
            let summary = baseSummary + [
                "firstUptime=\(firstAudioUptime)",
                "lastUptime=\(lastAudioUptime)",
                "firstSendUptime=\(firstSendQueued)",
                "firstSendActualUptime=\(firstSendActual)",
            ]
            DebugLog.recording(summary.joined(separator: " "))
        } else {
            let summary = baseSummary + [
                "firstUptime=nil",
                "lastUptime=nil",
                "firstSendUptime=\(firstSendQueued)",
                "firstSendActualUptime=\(firstSendActual)",
            ]
            DebugLog.recording(summary.joined(separator: " "))
        }

        let shouldAwaitCompletion = waitForCompletion

        if !realtimeFailedWhileRecording, !isRealtimeReady, let sessionUpdateTask {
            do {
                try await sessionUpdateTask.value
                markRealtimeReady(startCommitTimer: false)
            } catch {
                realtimeFailedWhileRecording = true
                errorMessage = error.localizedDescription
                closeRealtime()
            }
        }

        if realtimeFailedWhileRecording {
            closeRealtime()
            await startRestFallbackIfNeeded()
            status = .idle
            finalizeDictationInjectionIfNeeded()
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
                status = .idle
                finalizeDictationInjectionIfNeeded()
                return
            }
        } else {
            closeRealtime()
            status = .idle
            finalizeDictationInjectionIfNeeded()
            return
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

    private func markRealtimeReady(startCommitTimer: Bool) {
        guard !isRealtimeReady else { return }
        isRealtimeReady = true
        sessionUpdateTask = nil
        flushPendingAudio()
        if startCommitTimer {
            startCommitTimerIfNeeded(vadMode: recordingVADMode)
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
                toastPresenter.showToast("Retrying...")
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
        let displayText = transcriptStore.displayText
        transcript = displayText
        dictationInjector.apply(text: displayText)
        errorMessage = nil
        realtimeFailedWhileRecording = false
        pendingRestWavURL = nil
        restRetryTask?.cancel()
        restRetryTask = nil
        toastPresenter.clearToast()
    }

    private func showManualRetryAction(for wavURL: URL) {
        toastPresenter.showToast("Transcription failed")
        toastPresenter.showAction(title: "Retry") { [weak self] in
            Task { @MainActor in
                self?.toastPresenter.showToast("Retrying...")
                await self?.performRestTranscription(wavURL: wavURL, allowRetry: false)
            }
        }
    }

    private func enqueueAudioSend(_ data: Data) {
        guard !data.isEmpty else { return }
        hasBufferedAudio = true
        wavWriter?.append(data)
        if realtimeFailedWhileRecording {
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        audioBufferCount += 1
        if audioBufferCount == 1 {
            firstAudioUptime = now
            if let sessionID = recordingSessionID {
                DebugLog.recording("audio.buffer.first session=\(sessionID) bytes=\(data.count) uptime=\(now)")
            }
        }
        lastAudioUptime = now
        let previousTask = audioSendTask
        let client = client
        let isFirstSend = sendCount == 0
        sendCount += 1
        if isFirstSend {
            firstSendUptime = now
            if let sessionID = recordingSessionID {
                let queuedLog = [
                    "audio.send.queued_first",
                    "session=\(sessionID)",
                    "bytes=\(data.count)",
                    "uptime=\(now)",
                ].joined(separator: " ")
                DebugLog.recording(queuedLog)
            }
        }
        guard isRealtimeReady else {
            pendingAudio.append(data)
            return
        }
        scheduleAudioSend(data, previousTask: previousTask, client: client)
    }

    private func flushPendingAudio() {
        guard isRealtimeReady, !pendingAudio.isEmpty else { return }
        let buffered = pendingAudio
        pendingAudio.removeAll()
        for chunk in buffered {
            scheduleAudioSend(chunk, previousTask: audioSendTask, client: client)
        }
    }

    private func scheduleAudioSend(
        _ data: Data,
        previousTask: Task<Void, Never>?,
        client: (any RealtimeTranscriptionClient)?,
    ) {
        let sessionID = recordingSessionID
        audioSendTask = Task {
            if let previousTask {
                _ = await previousTask.value
            }
            if let client {
                let sendTime = ProcessInfo.processInfo.systemUptime
                var logFirstSend = false
                await MainActor.run {
                    actualSendCount += 1
                    if actualSendCount == 1 {
                        firstSendActualUptime = sendTime
                        logFirstSend = true
                    }
                }
                if logFirstSend, let sessionID {
                    let firstLog = [
                        "audio.send.first",
                        "session=\(sessionID)",
                        "bytes=\(data.count)",
                        "uptime=\(sendTime)",
                    ].joined(separator: " ")
                    DebugLog.recording(firstLog)
                }
                do {
                    try await client.sendAudio(data)
                    if logFirstSend, let sessionID {
                        let okLog = [
                            "audio.send.first.ok",
                            "session=\(sessionID)",
                            "uptime=\(ProcessInfo.processInfo.systemUptime)",
                        ].joined(separator: " ")
                        DebugLog.recording(okLog)
                    }
                } catch {
                    if logFirstSend, let sessionID {
                        let errorLog = [
                            "audio.send.first.error",
                            "session=\(sessionID)",
                            "uptime=\(ProcessInfo.processInfo.systemUptime)",
                            "error=\(error.localizedDescription)",
                        ].joined(separator: " ")
                        DebugLog.recording(errorLog)
                    }
                }
            }
        }
    }

    private func closeRealtime() {
        client?.close()
        client = nil
        receiveTask?.cancel()
        receiveTask = nil
        sessionUpdateTask?.cancel()
        sessionUpdateTask = nil
        audioSendTask?.cancel()
        audioSendTask = nil
        isRealtimeReady = false
        pendingAudio.removeAll()
        shouldCloseAfterCompletion = false
        awaitingCompletionItemId = nil
    }

    private func finalizeDictationInjectionIfNeeded() {
        guard !didFinishInjection else { return }
        didFinishInjection = true
        let result = dictationInjector.finishSession()
        guard result.requiresClipboardFallback else { return }
        let text = transcriptStore.displayText
        guard !text.isEmpty else { return }
        clipboardWriter(text)
        toastPresenter.showToast("Unable to insert text. Paste with Command+V.")
    }

    private struct PostApplyActions {
        var shouldFinalize = false
        var shouldCloseRealtime = false
        var shouldStartRestFallback = false
    }

    private func applyPostActions(_ actions: PostApplyActions) async {
        if actions.shouldCloseRealtime {
            closeRealtime()
        }
        if actions.shouldStartRestFallback {
            await startRestFallbackIfNeeded()
        }
        if actions.shouldFinalize {
            finalizeDictationInjectionIfNeeded()
        }
    }

    private func handleInputAudioCommitted(_ committed: InputAudioCommittedEvent) {
        transcriptStore.applyCommitted(committed)
        if shouldCloseAfterCompletion, awaitingCompletionItemId == nil {
            awaitingCompletionItemId = committed.itemId
        }
    }

    private func handleTranscriptionDelta(_ delta: TranscriptionDeltaEvent) {
        transcriptStore.applyDelta(delta)
    }

    private func handleTranscriptionCompleted(_ completed: TranscriptionCompletedEvent) -> PostApplyActions {
        transcriptStore.applyCompleted(completed)
        realtimeFailedWhileRecording = false
        guard shouldCloseAfterCompletion,
              let awaitingCompletionItemId,
              awaitingCompletionItemId == completed.itemId
        else {
            return PostApplyActions()
        }

        var actions = PostApplyActions()
        actions.shouldCloseRealtime = true
        actions.shouldFinalize = true
        return actions
    }

    private func handleError(_ message: String) -> PostApplyActions {
        errorMessage = message
        realtimeFailedWhileRecording = true
        if shouldCloseAfterCompletion {
            var actions = PostApplyActions()
            actions.shouldCloseRealtime = true
            actions.shouldStartRestFallback = true
            actions.shouldFinalize = true
            return actions
        }
        if status != .recording, status != .connecting {
            status = .error(message)
            notchOverlay.hide()
        }
        return PostApplyActions()
    }

    private func handle(_ event: RealtimeServerEvent) async {
        var actions = PostApplyActions()

        switch event {
        case let .inputAudioCommitted(committed):
            handleInputAudioCommitted(committed)
        case let .transcriptionDelta(delta):
            handleTranscriptionDelta(delta)
        case let .transcriptionCompleted(completed):
            actions = handleTranscriptionCompleted(completed)
        case let .error(message):
            actions = handleError(message)
        case .unknown:
            break
        }

        let displayText = transcriptStore.displayText
        transcript = displayText
        dictationInjector.apply(text: displayText)

        await applyPostActions(actions)
    }
}
