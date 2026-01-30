import CoreAudio
@testable import FloxBoxCore
import Foundation

final class TestRealtimeClient: RealtimeTranscriptionClient {
    private let stream: AsyncStream<RealtimeServerEvent>
    private let continuation: AsyncStream<RealtimeServerEvent>.Continuation

    private(set) var didClose = false
    private(set) var didConnect = false
    private(set) var sentAudio: [Data] = []
    private(set) var sessionUpdates: [RealtimeTranscriptionSessionUpdate] = []
    private(set) var commitCount = 0
    private(set) var clearCount = 0

    init() {
        var continuation: AsyncStream<RealtimeServerEvent>.Continuation!
        stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    var events: AsyncStream<RealtimeServerEvent> {
        stream
    }

    func connect() {
        didConnect = true
    }

    func sendSessionUpdate(_ update: RealtimeTranscriptionSessionUpdate) async throws {
        sessionUpdates.append(update)
    }

    func sendAudio(_ data: Data) async throws {
        sentAudio.append(data)
    }

    func commitAudio() async throws {
        commitCount += 1
    }

    func clearAudioBuffer() async throws {
        clearCount += 1
    }

    func close() {
        didClose = true
        continuation.finish()
    }

    func emit(_ event: RealtimeServerEvent) {
        continuation.yield(event)
    }
}

enum TestRealtimeError: Error {
    case sendFailed
}

final class FailingRealtimeClient: RealtimeTranscriptionClient {
    private let stream: AsyncStream<RealtimeServerEvent>
    private let continuation: AsyncStream<RealtimeServerEvent>.Continuation

    init() {
        var continuation: AsyncStream<RealtimeServerEvent>.Continuation!
        stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    var events: AsyncStream<RealtimeServerEvent> {
        stream
    }

    func connect() {}

    func sendSessionUpdate(_: RealtimeTranscriptionSessionUpdate) async throws {}

    func sendAudio(_: Data) async throws {
        throw TestRealtimeError.sendFailed
    }

    func commitAudio() async throws {}

    func clearAudioBuffer() async throws {}

    func close() {
        continuation.finish()
    }

    func emit(_ event: RealtimeServerEvent) {
        continuation.yield(event)
    }
}

final class BlockingRealtimeClient: RealtimeTranscriptionClient {
    private let stream: AsyncStream<RealtimeServerEvent>
    private let continuation: AsyncStream<RealtimeServerEvent>.Continuation
    private var sessionUpdateContinuation: CheckedContinuation<Void, Never>?
    private(set) var didConnect = false
    private(set) var didStartSessionUpdate = false
    private(set) var sentAudio: [Data] = []
    private(set) var sessionUpdates: [RealtimeTranscriptionSessionUpdate] = []
    private(set) var commitCount = 0
    private(set) var clearCount = 0

    init() {
        var continuation: AsyncStream<RealtimeServerEvent>.Continuation!
        stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    var events: AsyncStream<RealtimeServerEvent> {
        stream
    }

    func connect() {
        didConnect = true
    }

    func sendSessionUpdate(_ update: RealtimeTranscriptionSessionUpdate) async throws {
        didStartSessionUpdate = true
        await withCheckedContinuation { continuation in
            sessionUpdateContinuation = continuation
        }
        sessionUpdates.append(update)
    }

    func sendAudio(_ data: Data) async throws {
        sentAudio.append(data)
    }

    func commitAudio() async throws {
        commitCount += 1
    }

    func clearAudioBuffer() async throws {
        clearCount += 1
    }

    func close() {
        continuation.finish()
    }

    func unblockSessionUpdate() {
        sessionUpdateContinuation?.resume()
        sessionUpdateContinuation = nil
    }
}

final class TestAudioCapture: AudioCapturing {
    private var handler: ((Data) -> Void)?
    private(set) var isRunning = false
    private(set) var preferredDeviceID: AudioDeviceID?

    func setPreferredInputDevice(_ deviceID: AudioDeviceID?) {
        preferredDeviceID = deviceID
    }

    func start(handler: @escaping (Data) -> Void) throws {
        isRunning = true
        self.handler = handler
    }

    func stop() {
        isRunning = false
    }

    func emit(_ data: Data) {
        handler?(data)
    }
}

enum TestRestError: Error {
    case failure
}

final class TestRestClient: RestTranscriptionClientProtocol {
    enum Result {
        case success(String)
        case failure(Error)
    }

    private var results: [Result] = []
    private(set) var callCount = 0
    private(set) var lastFileURL: URL?
    private(set) var lastModel: String?
    private(set) var lastLanguage: String?
    private(set) var lastPrompt: String?

    func queueResults(_ results: [Result]) {
        self.results = results
    }

    func transcribe(fileURL: URL, model: String, language: String?, prompt: String?) async throws -> String {
        callCount += 1
        lastFileURL = fileURL
        lastModel = model
        lastLanguage = language
        lastPrompt = prompt

        guard !results.isEmpty else {
            return ""
        }

        let result = results.removeFirst()
        switch result {
        case let .success(text):
            return text
        case let .failure(error):
            throw error
        }
    }
}

final class TestFormattingClient: FormattingClientProtocol {
    enum Result {
        case success(String)
        case failure
    }

    private var results: [Result]
    private(set) var callCount = 0

    init(results: [Result]) {
        self.results = results
    }

    func format(text _: String, model _: FormattingModel, glossary _: [PersonalGlossaryEntry]) async throws -> String {
        callCount += 1
        guard !results.isEmpty else { return "" }
        switch results.removeFirst() {
        case let .success(value):
            return value
        case .failure:
            throw FormattingPipelineError.unknown
        }
    }
}

@MainActor
final class TestNotchOverlay: NotchRecordingControlling {
    private(set) var showCount = 0
    private(set) var showAwaitingNetworkCount = 0
    private(set) var showFormattingCount = 0
    private(set) var hideCount = 0
    private var cancelHandler: (() -> Void)?

    func showRecording() {
        showCount += 1
    }

    func showAwaitingNetwork(onCancel: @escaping () -> Void) {
        showAwaitingNetworkCount += 1
        cancelHandler = onCancel
    }

    func showFormatting() {
        showFormattingCount += 1
    }

    func hide() {
        hideCount += 1
    }

    func triggerCancel() {
        cancelHandler?()
    }
}

@MainActor
final class TestToastPresenter: ToastPresenting {
    private(set) var toastMessages: [String] = []
    private(set) var actionTitles: [String] = []

    func showToast(_ message: String) {
        toastMessages.append(message)
    }

    func showAction(title: String, handler _: @escaping () -> Void) {
        actionTitles.append(title)
    }

    func clearToast() {}
}

@MainActor
final class TestDictationInjector: DictationInjectionControlling {
    private(set) var startCount = 0
    private(set) var appliedTexts: [String] = []
    private(set) var insertedTexts: [String] = []
    private(set) var finishCount = 0
    private(set) var events: [String] = []
    var result = DictationInjectionResult(requiresManualPaste: false)

    func startSession() {
        startCount += 1
        events.append("start")
    }

    func apply(text: String) {
        appliedTexts.append(text)
        events.append("apply:\(text)")
    }

    func insertFinal(text: String) -> Bool {
        insertedTexts.append(text)
        events.append("insertFinal:\(text)")
        return !text.isEmpty
    }

    func finishSession() -> DictationInjectionResult {
        finishCount += 1
        events.append("finish")
        return result
    }
}
