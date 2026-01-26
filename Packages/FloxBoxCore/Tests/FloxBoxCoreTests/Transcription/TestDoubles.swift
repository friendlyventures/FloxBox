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

    func queueResults(_ results: [Result]) {
        self.results = results
    }

    func transcribe(fileURL: URL, model: String, language: String?) async throws -> String {
        callCount += 1
        lastFileURL = fileURL
        lastModel = model
        lastLanguage = language

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

@MainActor
final class TestNotchOverlay: NotchRecordingControlling {
    private(set) var showCount = 0
    private(set) var hideCount = 0
    private(set) var toastMessages: [String] = []
    private(set) var actionTitles: [String] = []

    func show() {
        showCount += 1
    }

    func hide() {
        hideCount += 1
    }

    func showToast(_ message: String) {
        toastMessages.append(message)
    }

    func showAction(title: String, handler _: @escaping () -> Void) {
        actionTitles.append(title)
    }

    func clearToast() {}
}
