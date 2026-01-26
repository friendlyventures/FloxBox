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
        )

        viewModel.apiKeyInput = "sk-test"
        await viewModel.startAndWait(trigger: .pushToTalk)
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
        )

        viewModel.apiKeyInput = "sk-test"
        await viewModel.startAndWait(trigger: .pushToTalk)
        audio.emit(Data([0x01]))
        await Task.yield()

        realtime.emit(.error("socket failed"))
        await viewModel.stopAndWait()
        try? await Task.sleep(nanoseconds: 5_000_000)

        XCTAssertEqual(rest.callCount, 2)
        XCTAssertEqual(viewModel.transcript, "Rest OK")
    }
}
