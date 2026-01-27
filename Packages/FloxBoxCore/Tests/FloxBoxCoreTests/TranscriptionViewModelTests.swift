@testable import FloxBoxCore
import XCTest

@MainActor
final class TranscriptionViewModelTests: XCTestCase {
    func testDefaults() {
        let viewModel = TranscriptionViewModel(keychain: InMemoryKeychainStore())
        XCTAssertEqual(viewModel.model, .defaultModel)
        XCTAssertEqual(viewModel.language, .defaultLanguage)
        XCTAssertEqual(viewModel.noiseReduction, .defaultOption)
        XCTAssertNil(viewModel.selectedInputDeviceID)
        XCTAssertEqual(viewModel.vadMode, .server)
        XCTAssertEqual(viewModel.manualCommitInterval, .defaultInterval)
        XCTAssertEqual(viewModel.status, .idle)
        XCTAssertEqual(viewModel.transcript, "")
        XCTAssertEqual(viewModel.apiKeyInput, "")
        XCTAssertEqual(viewModel.apiKeyStatus, .idle)
    }

    func testLoadsAPIKeyFromKeychain() {
        let keychain = InMemoryKeychainStore()
        try? keychain.save("sk-test")
        let viewModel = TranscriptionViewModel(keychain: keychain)

        XCTAssertEqual(viewModel.apiKeyInput, "sk-test")
    }

    func testSaveClearsKeychainWhenEmpty() {
        let keychain = InMemoryKeychainStore()
        let viewModel = TranscriptionViewModel(keychain: keychain)

        viewModel.apiKeyInput = ""
        viewModel.saveAPIKey()

        XCTAssertNil(try? keychain.load())
        XCTAssertEqual(viewModel.apiKeyStatus, .cleared)
    }

    func testStopWaitsForCompletedBeforeClosingRealtime() async {
        let realtime = TestRealtimeClient()
        let audio = TestAudioCapture()
        let rest = TestRestClient()
        let viewModel = TranscriptionViewModel(
            keychain: InMemoryKeychainStore(),
            audioCapture: audio,
            realtimeFactory: { _ in realtime },
            restClient: rest,
            permissionRequester: { true },
            notchOverlay: TestNotchOverlay(),
            pttTailNanos: 0,
            accessibilityChecker: { true },
            secureInputChecker: { false },
            permissionsPresenter: {},
            dictationInjector: TestDictationInjector(),
            clipboardWriter: { _ in },
        )

        viewModel.apiKeyInput = "sk-test"
        await viewModel.startAndWait()
        audio.emit(Data([0x01, 0x02]))
        await Task.yield()

        await viewModel.stopAndWait()
        XCTAssertFalse(realtime.didClose)

        realtime.emit(.inputAudioCommitted(.init(itemId: "item1", previousItemId: nil)))
        realtime.emit(.transcriptionCompleted(.init(itemId: "item1", contentIndex: 0, transcript: "Test")))
        try? await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertTrue(realtime.didClose)
        XCTAssertEqual(viewModel.transcript, "Test")
    }

    func testRealtimeFailureFallsBackToRestWithSingleRetry() async {
        let realtime = TestRealtimeClient()
        let audio = TestAudioCapture()
        let rest = TestRestClient()
        rest.queueResults([.failure(TestRestError.failure), .success("Rest OK")])

        let viewModel = TranscriptionViewModel(
            keychain: InMemoryKeychainStore(),
            audioCapture: audio,
            realtimeFactory: { _ in realtime },
            restClient: rest,
            permissionRequester: { true },
            notchOverlay: TestNotchOverlay(),
            restRetryDelayNanos: 1_000_000,
            pttTailNanos: 0,
            accessibilityChecker: { true },
            secureInputChecker: { false },
            permissionsPresenter: {},
            dictationInjector: TestDictationInjector(),
            clipboardWriter: { _ in },
        )

        viewModel.apiKeyInput = "sk-test"
        await viewModel.startAndWait()
        audio.emit(Data([0x01]))
        await Task.yield()

        realtime.emit(.error("socket failed"))
        await viewModel.stopAndWait()
        try? await Task.sleep(nanoseconds: 5_000_000)

        XCTAssertEqual(rest.callCount, 2)
        XCTAssertEqual(viewModel.transcript, "Rest OK")
    }

    func testStartResetsTranscriptBetweenSessions() async {
        var clients: [TestRealtimeClient] = []
        let audio = TestAudioCapture()
        let viewModel = TranscriptionViewModel(
            keychain: InMemoryKeychainStore(),
            audioCapture: audio,
            realtimeFactory: { _ in
                let client = TestRealtimeClient()
                clients.append(client)
                return client
            },
            restClient: TestRestClient(),
            permissionRequester: { true },
            notchOverlay: TestNotchOverlay(),
            pttTailNanos: 0,
            accessibilityChecker: { true },
            secureInputChecker: { false },
            permissionsPresenter: {},
            dictationInjector: TestDictationInjector(),
            clipboardWriter: { _ in },
        )

        viewModel.apiKeyInput = "sk-test"
        await viewModel.startAndWait()
        XCTAssertEqual(clients.count, 1)
        clients[0].emit(.inputAudioCommitted(.init(itemId: "item-1", previousItemId: nil)))
        clients[0].emit(.transcriptionCompleted(.init(itemId: "item-1", contentIndex: 0, transcript: "First")))
        try? await Task.sleep(nanoseconds: 5_000_000)
        XCTAssertEqual(viewModel.transcript, "First")
        await viewModel.stopAndWait()

        await viewModel.startAndWait()
        XCTAssertEqual(clients.count, 2)
        clients[1].emit(.inputAudioCommitted(.init(itemId: "item-2", previousItemId: nil)))
        clients[1].emit(.transcriptionCompleted(.init(itemId: "item-2", contentIndex: 0, transcript: "Second")))
        try? await Task.sleep(nanoseconds: 5_000_000)
        XCTAssertEqual(viewModel.transcript, "Second")
    }

    func testCompletionFinalizesAfterApplyingLatestTranscript() async {
        let realtime = TestRealtimeClient()
        let audio = TestAudioCapture()
        let injector = TestDictationInjector()
        let viewModel = TranscriptionViewModel(
            keychain: InMemoryKeychainStore(),
            audioCapture: audio,
            realtimeFactory: { _ in realtime },
            restClient: TestRestClient(),
            permissionRequester: { true },
            notchOverlay: TestNotchOverlay(),
            toastPresenter: TestToastPresenter(),
            pttTailNanos: 0,
            accessibilityChecker: { true },
            secureInputChecker: { false },
            permissionsPresenter: {},
            dictationInjector: injector,
            clipboardWriter: { _ in },
        )

        viewModel.apiKeyInput = "sk-test"
        await viewModel.startAndWait()
        audio.emit(Data([0x01, 0x02]))
        await Task.yield()
        await viewModel.stopAndWait()

        realtime.emit(.inputAudioCommitted(.init(itemId: "item-1", previousItemId: nil)))
        realtime.emit(.transcriptionCompleted(.init(itemId: "item-1", contentIndex: 0, transcript: "Hello")))
        try? await Task.sleep(nanoseconds: 10_000_000)

        guard let applyIndex = injector.events.firstIndex(of: "apply:Hello"),
              let finishIndex = injector.events.firstIndex(of: "finish")
        else {
            XCTFail("Expected apply and finish events")
            return
        }
        XCTAssertLessThan(applyIndex, finishIndex)
    }

    func testStartBeginsRecordingBeforeSessionUpdateCompletesAndBuffersAudio() async {
        let realtime = BlockingRealtimeClient()
        let audio = TestAudioCapture()
        let viewModel = TranscriptionViewModel(
            keychain: InMemoryKeychainStore(),
            audioCapture: audio,
            realtimeFactory: { _ in realtime },
            restClient: TestRestClient(),
            permissionRequester: { true },
            notchOverlay: TestNotchOverlay(),
            toastPresenter: TestToastPresenter(),
            pttTailNanos: 0,
            accessibilityChecker: { true },
            secureInputChecker: { false },
            permissionsPresenter: {},
            dictationInjector: TestDictationInjector(),
            clipboardWriter: { _ in },
        )

        viewModel.apiKeyInput = "sk-test"

        let startTask = Task { await viewModel.startAndWait() }
        for _ in 0 ..< 5 {
            if realtime.didStartSessionUpdate {
                break
            }
            await Task.yield()
        }

        XCTAssertTrue(realtime.didStartSessionUpdate)
        XCTAssertTrue(audio.isRunning)
        XCTAssertEqual(viewModel.status, .recording)

        audio.emit(Data([0x0A, 0x0B]))
        await Task.yield()
        XCTAssertEqual(realtime.sentAudio, [])

        realtime.unblockSessionUpdate()
        _ = await startTask.value
        for _ in 0 ..< 10 {
            if realtime.sentAudio == [Data([0x0A, 0x0B])] {
                break
            }
            await Task.yield()
        }

        XCTAssertEqual(realtime.sentAudio, [Data([0x0A, 0x0B])])
    }
}
