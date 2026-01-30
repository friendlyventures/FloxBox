import AppKit
import Carbon
import CoreAudio
import Foundation
import Observation

// swiftlint:disable file_length
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
    func showRecording()
    func showAwaitingNetwork(onCancel: @escaping () -> Void)
    func showFormatting()
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
    You are a transcription assistant. Transcribe the spoken audio accurately and fluently.
    Return well-formed sentences and paragraphs that read as if written contiguously.
    Remove disfluencies (e.g., "um", "uh", "like", "you know") and false starts unless clearly intended.
    Insert punctuation and capitalization based on meaning and context.
    Use paragraph breaks only for topic shifts or when the speaker explicitly indicates a new paragraph.
    Do not use pauses or timing alone to create paragraph breaks.
    Do not add, omit, or rephrase content beyond cleaning disfluencies and formatting. No timestamps or commentary.
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
    public var lastFinalTranscript: String?
    public var lastRawTranscript: String?
    public var lastTranscriptWasFormatted: Bool = false
    public var formattingStatus: FormattingStatus = .idle
    public var dictationAudioHistorySessions: [DictationSessionRecord] = []
    public let wireAudioPlayback = WireAudioPlaybackController()
    public var status: RecordingStatus = .idle
    public var errorMessage: String?

    public var isFormattingEnabled: Bool {
        formattingSettings.isEnabled
    }

    private let audioCapture: any AudioCapturing
    private let transcriptStore = TranscriptStore()
    private let keychain: any KeychainStoring
    private let realtimeFactory: (String) -> any RealtimeTranscriptionClient
    private let restClient: (any RestTranscriptionClientProtocol)?
    private let formattingSettings: FormattingSettingsStore
    private let glossaryStore: PersonalGlossaryStore
    private let formattingClientFactory: (String) -> FormattingClientProtocol
    private let permissionRequester: () async -> Bool
    private let accessibilityChecker: () -> Bool
    private let secureInputChecker: () -> Bool
    private let permissionsPresenter: () -> Void
    private let dictationInjector: any DictationInjectionControlling
    private let clipboardWriter: (String) -> Void
    private let notchOverlay: any NotchRecordingControlling
    private let toastPresenter: any ToastPresenting
    private let audioHistoryStore: DictationAudioHistoryStore
    private let audioHistoryRecorder: WireAudioHistoryRecorder
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
    private var restTranscriptionTask: Task<Void, Never>?
    private var completionTimeoutTask: Task<Void, Never>?
    private var restRetryDelayNanos: UInt64
    private var realtimeCompletionTimeoutNanos: UInt64
    private var restTimeoutNanos: UInt64
    private var isRestTranscribing = false
    private var pttTailNanos: UInt64
    private var formattingTask: Task<Void, Never>?
    private var isFormattingFinalTranscript = false
    private var didFinishInjection = false
    private var didInsertFinalTranscript = false
    private var didEndAudioHistorySession = false

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
        realtimeCompletionTimeoutNanos: UInt64 = 5_000_000_000,
        restTimeoutNanos: UInt64 = 5_000_000_000,
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
        audioHistoryStore: DictationAudioHistoryStore? = nil,
        formattingSettings: FormattingSettingsStore = FormattingSettingsStore(),
        glossaryStore: PersonalGlossaryStore = PersonalGlossaryStore(),
        formattingClientFactory: @escaping (String)
            -> FormattingClientProtocol = { OpenAIFormattingClient(apiKey: $0) },
    ) {
        self.keychain = keychain
        self.audioCapture = audioCapture
        self.realtimeFactory = realtimeFactory
        self.restClient = restClient
        self.formattingSettings = formattingSettings
        self.glossaryStore = glossaryStore
        self.formattingClientFactory = formattingClientFactory
        self.permissionRequester = permissionRequester
        self.accessibilityChecker = accessibilityChecker
        self.secureInputChecker = secureInputChecker
        self.permissionsPresenter = permissionsPresenter
        self.dictationInjector = dictationInjector ?? DictationInjectionController()
        self.clipboardWriter = clipboardWriter
        self.notchOverlay = notchOverlay ?? NotchRecordingController()
        self.toastPresenter = toastPresenter ?? SystemNotificationPresenter()
        let resolvedAudioHistoryStore = audioHistoryStore ?? DictationAudioHistoryStore()
        self.audioHistoryStore = resolvedAudioHistoryStore
        audioHistoryRecorder = WireAudioHistoryRecorder(store: resolvedAudioHistoryStore)
        dictationAudioHistorySessions = (try? resolvedAudioHistoryStore.load()) ?? []
        self.restRetryDelayNanos = restRetryDelayNanos
        self.realtimeCompletionTimeoutNanos = realtimeCompletionTimeoutNanos
        self.restTimeoutNanos = restTimeoutNanos
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

    public var dictationAudioHistoryBaseURL: URL {
        audioHistoryStore.baseURL
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
        formattingStatus = .idle
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
        guard status != .recording, status != .awaitingNetwork else { return }
        let sessionID = String(UUID().uuidString.prefix(8))
        recordingSessionID = sessionID
        resetRecordingState(sessionID: sessionID)

        guard let apiKey = await validateStart(sessionID: sessionID) else { return }

        beginDictationSession(sessionID: sessionID)
        let client = startRealtimeClient(apiKey: apiKey, sessionID: sessionID)
        guard startAudioCapture(sessionID: sessionID) else { return }

        status = .recording
        DebugLog.recording(logStatusChange("status.recording", sessionID: sessionID))
        notchOverlay.showRecording()

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
        restTranscriptionTask?.cancel()
        restTranscriptionTask = nil
        completionTimeoutTask?.cancel()
        completionTimeoutTask = nil
        isRestTranscribing = false
        formattingTask?.cancel()
        formattingTask = nil
        isFormattingFinalTranscript = false
        formattingStatus = .idle
        pendingRestWavURL = nil
        didFinishInjection = false
        didInsertFinalTranscript = false
        didEndAudioHistorySession = false
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

    private func beginDictationSession(sessionID: String) {
        transcriptStore.reset()
        transcript = ""
        ShortcutDebugLogger.log("dictation.start transcriptReset")
        dictationInjector.startSession()
        ShortcutDebugLogger.log("dictation.start sessionBegin")
        prepareWavCapture()
        Task { [weak self] in
            guard let self else { return }
            await audioHistoryRecorder.startSession(sessionID: sessionID, startedAt: Date())
            await refreshAudioHistory()
        }
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

        commitTask?.cancel()
        commitTask = nil
        await applyPttTailIfNeeded(sessionID: sessionID)
        audioCapture.stop()
        await Task.yield()
        finalizeWavCapture()
        let firstSendQueued = firstSendUptime.map { String(describing: $0) } ?? "nil"
        let firstSendActual = firstSendActualUptime.map { String(describing: $0) } ?? "nil"
        logAudioSummary(
            sessionID: sessionID,
            firstSendQueued: firstSendQueued,
            firstSendActual: firstSendActual,
        )

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
            beginAwaitingNetwork()
            if !startRestFallbackIfNeeded() {
                endAwaitingNetwork()
                finalizeDictationInjectionIfNeeded()
            }
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
                notchOverlay.hide()
                return
            }
            beginAwaitingNetwork()
            startRealtimeCompletionTimeout()
            return
        } else {
            closeRealtime()
            status = .idle
            finalizeDictationInjectionIfNeeded()
            notchOverlay.hide()
            return
        }
    }

    private func applyPttTailIfNeeded(sessionID: String) async {
        guard status == .recording, pttTailNanos > 0 else { return }
        try? await Task.sleep(nanoseconds: pttTailNanos)
        let tailLog = [
            "ptt.tail.complete",
            "session=\(sessionID)",
            "tailNanos=\(pttTailNanos)",
            "uptime=\(ProcessInfo.processInfo.systemUptime)",
        ].joined(separator: " ")
        DebugLog.recording(tailLog)
    }

    private func logAudioSummary(sessionID: String, firstSendQueued: String, firstSendActual: String) {
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
    }

    private func beginAwaitingNetwork() {
        guard status != .awaitingNetwork else { return }
        status = .awaitingNetwork
        notchOverlay.showAwaitingNetwork { [weak self] in
            Task { @MainActor in
                self?.cancelPendingNetwork()
            }
        }
    }

    private func endAwaitingNetwork() {
        completionTimeoutTask?.cancel()
        completionTimeoutTask = nil
        restRetryTask?.cancel()
        restRetryTask = nil
        restTranscriptionTask?.cancel()
        restTranscriptionTask = nil
        status = .idle
        notchOverlay.hide()
    }

    private func cancelPendingNetwork() {
        completionTimeoutTask?.cancel()
        completionTimeoutTask = nil
        restRetryTask?.cancel()
        restRetryTask = nil
        restTranscriptionTask?.cancel()
        restTranscriptionTask = nil
        isRestTranscribing = false
        formattingTask?.cancel()
        formattingTask = nil
        isFormattingFinalTranscript = false
        formattingStatus = .idle
        if let pendingRestWavURL {
            try? FileManager.default.removeItem(at: pendingRestWavURL)
        }
        pendingRestWavURL = nil
        latestWavURL = nil
        closeRealtime()
        endAwaitingNetwork()
        finalizeDictationInjectionIfNeeded()
    }

    private func startRealtimeCompletionTimeout() {
        completionTimeoutTask?.cancel()
        completionTimeoutTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: realtimeCompletionTimeoutNanos)
            guard !Task.isCancelled, status == .awaitingNetwork else { return }
            closeRealtime()
            if !startRestFallbackIfNeeded() {
                endAwaitingNetwork()
                finalizeDictationInjectionIfNeeded()
            }
        }
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

    private func refreshAudioHistory() async {
        dictationAudioHistorySessions = await audioHistoryRecorder.sessionsSnapshot()
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

    @discardableResult
    private func startRestFallbackIfNeeded() -> Bool {
        guard let wavURL = pendingRestWavURL else { return false }
        restTranscriptionTask?.cancel()
        restTranscriptionTask = Task { @MainActor [weak self] in
            await self?.performRestTranscription(wavURL: wavURL, allowRetry: true)
        }
        return true
    }

    private func performRestTranscription(wavURL: URL, allowRetry: Bool) async {
        guard !Task.isCancelled else { return }
        guard !isRestTranscribing else { return }
        guard let restClient = restClientForSession() else { return }

        isRestTranscribing = true
        defer { isRestTranscribing = false }

        do {
            let text = try await withTimeout(nanos: restTimeoutNanos) { [self] in
                try await restClient.transcribe(
                    fileURL: wavURL,
                    model: model.rawValue,
                    language: language.code,
                    prompt: normalizedPrompt,
                )
            }
            applyRestTranscription(text)
            endAwaitingNetwork()
            finalizeDictationInjectionIfNeeded()
        } catch {
            guard !Task.isCancelled else { return }
            if allowRetry {
                restRetryTask?.cancel()
                restRetryTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    try? await Task.sleep(nanoseconds: restRetryDelayNanos)
                    await performRestTranscription(wavURL: wavURL, allowRetry: false)
                }
            } else {
                toastPresenter.showToast("Dictation failed — check your network")
                endAwaitingNetwork()
                finalizeDictationInjectionIfNeeded()
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

    private struct TimeoutError: Error {}

    private func withTimeout<T>(
        nanos: UInt64,
        operation: @escaping () async throws -> T,
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: nanos)
                throw TimeoutError()
            }
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            group.cancelAll()
            return result
        }
    }

    private func applyRestTranscription(_ text: String) {
        transcriptStore.appendFinalText(text)
        let displayText = transcriptStore.displayText
        transcript = displayText
        finalizeTranscript(rawText: displayText)
        errorMessage = nil
        realtimeFailedWhileRecording = false
        pendingRestWavURL = nil
        restRetryTask?.cancel()
        restRetryTask = nil
        toastPresenter.clearToast()
    }

    private func finalizeTranscript(rawText: String) {
        lastRawTranscript = rawText
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            finalizeDictationInjectionIfNeeded()
            return
        }

        guard formattingSettings.isEnabled else {
            formattingStatus = .idle
            insertFinalTranscriptIfNeeded(text: rawText, wasFormatted: false)
            finalizeDictationInjectionIfNeeded()
            return
        }

        guard let pipeline = formattingPipelineForSession() else {
            formattingStatus = .failed("Missing API key")
            handleFormattingFailure(
                message: "Formatting unavailable — missing API key",
                rawText: rawText,
            )
            finalizeDictationInjectionIfNeeded()
            return
        }

        formattingTask?.cancel()
        formattingTask = Task { @MainActor [weak self] in
            await self?.runFormatting(rawText: rawText, pipeline: pipeline)
        }
    }

    private func formattingPipelineForSession() -> FormattingPipeline? {
        guard let apiKey = activeAPIKey else { return nil }
        let client = formattingClientFactory(apiKey)
        return FormattingPipeline(client: client)
    }

    @MainActor
    private func runFormatting(rawText: String, pipeline: FormattingPipeline) async {
        isFormattingFinalTranscript = true
        formattingStatus = .formatting(attempt: 1, maxAttempts: 1)
        notchOverlay.showFormatting()
        toastPresenter.showToast("Polishing transcript…")

        do {
            let formatted = try await pipeline.format(
                text: rawText,
                model: formattingSettings.model,
                glossary: glossaryStore.activeEntries,
                onAttempt: { [weak self] attempt, maxAttempts in
                    guard let self else { return }
                    formattingStatus = .formatting(attempt: attempt, maxAttempts: maxAttempts)
                    if attempt > 1 {
                        toastPresenter.showToast(
                            "Retrying transcript formatting (attempt \(attempt) of \(maxAttempts))",
                        )
                    }
                },
            )
            transcript = formatted
            insertFinalTranscriptIfNeeded(text: formatted, wasFormatted: true)
            formattingStatus = .completed
            toastPresenter.clearToast()
        } catch {
            formattingStatus = .failed(error.localizedDescription)
            handleFormattingFailure(
                message: "Formatting failed — use Menu Bar → Paste last transcript (raw)",
                rawText: rawText,
            )
        }

        isFormattingFinalTranscript = false
        notchOverlay.hide()
        finalizeDictationInjectionIfNeeded()
    }

    private func handleFormattingFailure(message: String, rawText: String) {
        lastFinalTranscript = rawText
        lastTranscriptWasFormatted = false
        toastPresenter.showToast(message)
        toastPresenter.showAction(title: "Paste raw transcript") { [weak self] in
            self?.pasteLastTranscript()
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
                    await audioHistoryRecorder.appendSentAudio(data)
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
        completionTimeoutTask?.cancel()
        completionTimeoutTask = nil
    }

    private func finalizeDictationInjectionIfNeeded() {
        finalizeAudioHistorySessionIfNeeded()
        guard !isFormattingFinalTranscript else { return }
        guard !didFinishInjection else { return }
        didFinishInjection = true
        let result = dictationInjector.finishSession()
        guard result.requiresManualPaste else { return }
        guard didInsertFinalTranscript else { return }
        guard let text = lastFinalTranscript, !text.isEmpty else { return }
        toastPresenter.showToast("Unable to insert text. Use Menu Bar → Paste last transcript.")
    }

    private func finalizeAudioHistorySessionIfNeeded() {
        guard !didEndAudioHistorySession else { return }
        didEndAudioHistorySession = true
        Task { [weak self] in
            guard let self else { return }
            await audioHistoryRecorder.endSession(endedAt: Date())
            await refreshAudioHistory()
        }
    }

    private struct PostApplyActions {
        var shouldFinalize = false
        var shouldCloseRealtime = false
        var shouldStartRestFallback = false
        var shouldEndAwaitingNetwork = false
    }

    private func applyPostActions(_ actions: PostApplyActions) async {
        if actions.shouldCloseRealtime {
            closeRealtime()
        }
        if actions.shouldStartRestFallback {
            beginAwaitingNetwork()
            if !startRestFallbackIfNeeded() {
                finalizeDictationInjectionIfNeeded()
                endAwaitingNetwork()
            }
        }
        if actions.shouldFinalize {
            finalizeDictationInjectionIfNeeded()
        }
        if actions.shouldEndAwaitingNetwork {
            endAwaitingNetwork()
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

        finalizeTranscript(rawText: transcriptStore.displayText)
        var actions = PostApplyActions()
        actions.shouldCloseRealtime = true
        actions.shouldFinalize = true
        actions.shouldEndAwaitingNetwork = true
        return actions
    }

    private func handleError(_ message: String) -> PostApplyActions {
        errorMessage = message
        realtimeFailedWhileRecording = true
        if shouldCloseAfterCompletion {
            var actions = PostApplyActions()
            actions.shouldCloseRealtime = true
            actions.shouldStartRestFallback = true
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
            await audioHistoryRecorder.commit(itemId: committed.itemId, createdAt: Date())
            await refreshAudioHistory()
        case let .transcriptionDelta(delta):
            handleTranscriptionDelta(delta)
        case let .transcriptionCompleted(completed):
            actions = handleTranscriptionCompleted(completed)
            await audioHistoryRecorder.updateTranscript(itemId: completed.itemId, text: completed.transcript)
            await refreshAudioHistory()
        case let .error(message):
            actions = handleError(message)
        case .unknown:
            break
        }

        let displayText = transcriptStore.displayText
        transcript = displayText

        await applyPostActions(actions)
    }

    private func insertFinalTranscriptIfNeeded(text: String, wasFormatted: Bool) {
        guard !didInsertFinalTranscript else { return }
        guard !text.isEmpty else { return }
        lastFinalTranscript = text
        lastTranscriptWasFormatted = wasFormatted
        _ = dictationInjector.insertFinal(text: text)
        didInsertFinalTranscript = true
    }

    public func pasteLastTranscript() {
        guard let text = lastFinalTranscript, !text.isEmpty else { return }
        dictationInjector.startSession()
        _ = dictationInjector.insertFinal(text: text)
        let result = dictationInjector.finishSession()
        if result.requiresManualPaste {
            toastPresenter.showToast("Unable to insert text. Use Menu Bar → Paste last transcript.")
        }
    }
}
