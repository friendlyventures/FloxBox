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

    func testDefaultPromptAvoidsPauseBasedParagraphing() {
        let viewModel = TranscriptionViewModel(keychain: InMemoryKeychainStore())
        XCTAssertTrue(
            viewModel.transcriptionPrompt
                .contains("Do not use pauses or timing alone to create paragraph breaks."),
        )
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
        for _ in 0 ..< 10 where realtime.sentAudio.isEmpty {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertFalse(realtime.sentAudio.isEmpty)

        await viewModel.stopAndWait()
        XCTAssertFalse(realtime.didClose)

        realtime.emit(.inputAudioCommitted(.init(itemId: "item1", previousItemId: nil)))
        realtime.emit(.transcriptionCompleted(.init(itemId: "item1", contentIndex: 0, transcript: "Test")))
        try? await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertTrue(realtime.didClose)
        XCTAssertEqual(viewModel.transcript, "Test")
    }

    func testStopFormatsTranscriptBeforeInsert() async {
        let realtime = TestRealtimeClient()
        let audio = TestAudioCapture()
        let toast = TestToastPresenter()
        let injector = TestDictationInjector()
        let keychain = InMemoryKeychainStore()
        let settingsSuite = UUID().uuidString
        let settingsDefaults = UserDefaults(suiteName: settingsSuite)!
        settingsDefaults.removePersistentDomain(forName: settingsSuite)
        let formattingSettings = FormattingSettingsStore(userDefaults: settingsDefaults)
        let glossaryDefaults = UserDefaults(suiteName: UUID().uuidString)!
        let glossaryStore = PersonalGlossaryStore(userDefaults: glossaryDefaults)
        let formattingClient = TestFormattingClient(results: [.success("Raw text.")])

        let viewModel = TranscriptionViewModel(
            keychain: keychain,
            audioCapture: audio,
            realtimeFactory: { _ in realtime },
            restClient: TestRestClient(),
            permissionRequester: { true },
            notchOverlay: TestNotchOverlay(),
            toastPresenter: toast,
            pttTailNanos: 0,
            accessibilityChecker: { true },
            secureInputChecker: { false },
            permissionsPresenter: {},
            dictationInjector: injector,
            clipboardWriter: { _ in },
            formattingSettings: formattingSettings,
            glossaryStore: glossaryStore,
            formattingClientFactory: { _ in formattingClient },
        )

        viewModel.apiKeyInput = "sk-test"
        await viewModel.startAndWait()
        audio.emit(Data([0x01]))

        await viewModel.stopAndWait()
        realtime.emit(.inputAudioCommitted(.init(itemId: "item1", previousItemId: nil)))
        realtime.emit(.transcriptionCompleted(.init(itemId: "item1", contentIndex: 0, transcript: "Raw text")))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(injector.insertedTexts.last, "Raw text.")
        XCTAssertTrue(viewModel.lastTranscriptWasFormatted)
    }

    func testStopFormatsTranscriptShowsNotchFormattingIndicator() async {
        let realtime = TestRealtimeClient()
        let audio = TestAudioCapture()
        let toast = TestToastPresenter()
        let injector = TestDictationInjector()
        let keychain = InMemoryKeychainStore()
        let settingsSuite = UUID().uuidString
        let settingsDefaults = UserDefaults(suiteName: settingsSuite)!
        settingsDefaults.removePersistentDomain(forName: settingsSuite)
        let formattingSettings = FormattingSettingsStore(userDefaults: settingsDefaults)
        let glossaryStore = PersonalGlossaryStore(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        let formattingClient = TestFormattingClient(results: [.success("Raw text.")])
        let overlay = TestNotchOverlay()

        let viewModel = TranscriptionViewModel(
            keychain: keychain,
            audioCapture: audio,
            realtimeFactory: { _ in realtime },
            restClient: TestRestClient(),
            permissionRequester: { true },
            notchOverlay: overlay,
            toastPresenter: toast,
            pttTailNanos: 0,
            accessibilityChecker: { true },
            secureInputChecker: { false },
            permissionsPresenter: {},
            dictationInjector: injector,
            clipboardWriter: { _ in },
            formattingSettings: formattingSettings,
            glossaryStore: glossaryStore,
            formattingClientFactory: { _ in formattingClient },
        )

        viewModel.apiKeyInput = "sk-test"
        await viewModel.startAndWait()
        audio.emit(Data([0x01]))

        await viewModel.stopAndWait()
        realtime.emit(.inputAudioCommitted(.init(itemId: "item1", previousItemId: nil)))
        realtime.emit(.transcriptionCompleted(.init(itemId: "item1", contentIndex: 0, transcript: "Raw text")))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(overlay.showFormattingCount, 1)
        XCTAssertGreaterThanOrEqual(overlay.hideCount, 1)
    }

    func testWireAudioHistoryCreatesChunkOnCommit() async throws {
        let realtime = TestRealtimeClient()
        let audio = TestAudioCapture()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = DictationAudioHistoryStore(baseURL: base)

        let viewModel = TranscriptionViewModel(
            keychain: InMemoryKeychainStore(),
            audioCapture: audio,
            realtimeFactory: { _ in realtime },
            restClient: TestRestClient(),
            permissionRequester: { true },
            notchOverlay: TestNotchOverlay(),
            pttTailNanos: 0,
            accessibilityChecker: { true },
            secureInputChecker: { false },
            permissionsPresenter: {},
            dictationInjector: TestDictationInjector(),
            clipboardWriter: { _ in },
            audioHistoryStore: store,
        )

        viewModel.apiKeyInput = "sk-test"
        await viewModel.startAndWait()
        audio.emit(Data([0x01, 0x02]))
        await Task.yield()

        realtime.emit(.inputAudioCommitted(.init(itemId: "item-1", previousItemId: nil)))
        realtime.emit(.transcriptionCompleted(.init(itemId: "item-1", contentIndex: 0, transcript: "Hello")))
        try? await Task.sleep(nanoseconds: 5_000_000)

        let sessions = viewModel.dictationAudioHistorySessions
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.chunks.first?.id, "item-1")
        XCTAssertEqual(sessions.first?.chunks.first?.transcript, "Hello")
    }

    func testWireAudioHistorySkipsFailedSend() async throws {
        let realtime = FailingRealtimeClient()
        let audio = TestAudioCapture()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = DictationAudioHistoryStore(baseURL: base)

        let viewModel = TranscriptionViewModel(
            keychain: InMemoryKeychainStore(),
            audioCapture: audio,
            realtimeFactory: { _ in realtime },
            restClient: TestRestClient(),
            permissionRequester: { true },
            notchOverlay: TestNotchOverlay(),
            pttTailNanos: 0,
            accessibilityChecker: { true },
            secureInputChecker: { false },
            permissionsPresenter: {},
            dictationInjector: TestDictationInjector(),
            clipboardWriter: { _ in },
            audioHistoryStore: store,
        )

        viewModel.apiKeyInput = "sk-test"
        await viewModel.startAndWait()
        audio.emit(Data([0x01, 0x02]))
        await Task.yield()

        realtime.emit(.inputAudioCommitted(.init(itemId: "item-1", previousItemId: nil)))
        try? await Task.sleep(nanoseconds: 5_000_000)

        let sessions = viewModel.dictationAudioHistorySessions
        XCTAssertEqual(sessions.first?.chunks.first?.byteCount ?? 0, 0)
    }

    func testWireAudioHistoryCreatesFallbackChunkWhenNoCommitEvent() async throws {
        let realtime = TestRealtimeClient()
        let audio = TestAudioCapture()
        let rest = TestRestClient()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = DictationAudioHistoryStore(baseURL: base)

        let viewModel = TranscriptionViewModel(
            keychain: InMemoryKeychainStore(),
            audioCapture: audio,
            realtimeFactory: { _ in realtime },
            restClient: rest,
            permissionRequester: { true },
            notchOverlay: TestNotchOverlay(),
            restRetryDelayNanos: 1_000_000,
            realtimeCompletionTimeoutNanos: 1_000_000,
            restTimeoutNanos: 5_000_000,
            pttTailNanos: 0,
            accessibilityChecker: { true },
            secureInputChecker: { false },
            permissionsPresenter: {},
            dictationInjector: TestDictationInjector(),
            clipboardWriter: { _ in },
            audioHistoryStore: store,
        )

        viewModel.apiKeyInput = "sk-test"
        await viewModel.startAndWait()
        audio.emit(Data([0x01, 0x02]))
        for _ in 0 ..< 10 where realtime.sentAudio.isEmpty {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertFalse(realtime.sentAudio.isEmpty)

        await viewModel.stopAndWait()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let sessions = viewModel.dictationAudioHistorySessions
        XCTAssertEqual(sessions.count, 1)
        let chunkId = sessions.first?.chunks.first?.id ?? ""
        XCTAssertTrue(chunkId.hasPrefix("uncommitted-"))
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

    func testRealtimeCompletionTimeoutFallsBackToRest() async {
        let realtime = TestRealtimeClient()
        let audio = TestAudioCapture()
        let rest = TestRestClient()
        rest.queueResults([.success("Rest OK")])
        let overlay = TestNotchOverlay()

        let viewModel = TranscriptionViewModel(
            keychain: InMemoryKeychainStore(),
            audioCapture: audio,
            realtimeFactory: { _ in realtime },
            restClient: rest,
            permissionRequester: { true },
            notchOverlay: overlay,
            realtimeCompletionTimeoutNanos: 1_000_000,
            restTimeoutNanos: 1_000_000,
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

        await viewModel.stopAndWait()
        try? await Task.sleep(nanoseconds: 5_000_000)

        XCTAssertEqual(rest.callCount, 1)
        XCTAssertEqual(viewModel.transcript, "Rest OK")
        XCTAssertEqual(viewModel.status, .idle)
        XCTAssertEqual(overlay.hideCount, 1)
    }

    func testFinalRestFailureNotifiesAndReturnsIdle() async {
        let realtime = TestRealtimeClient()
        let audio = TestAudioCapture()
        let rest = TestRestClient()
        rest.queueResults([.failure(TestRestError.failure), .failure(TestRestError.failure)])
        let toast = TestToastPresenter()

        let viewModel = TranscriptionViewModel(
            keychain: InMemoryKeychainStore(),
            audioCapture: audio,
            realtimeFactory: { _ in realtime },
            restClient: rest,
            permissionRequester: { true },
            notchOverlay: TestNotchOverlay(),
            toastPresenter: toast,
            restRetryDelayNanos: 1_000_000,
            restTimeoutNanos: 1_000_000,
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
        XCTAssertEqual(toast.toastMessages.last, "Dictation failed — check your network")
        XCTAssertTrue(toast.actionTitles.isEmpty)
        XCTAssertEqual(viewModel.status, .idle)
    }

    func testCancelStopsPendingNetworkAndReturnsIdle() async {
        let realtime = TestRealtimeClient()
        let audio = TestAudioCapture()
        let rest = TestRestClient()
        let overlay = TestNotchOverlay()

        let viewModel = TranscriptionViewModel(
            keychain: InMemoryKeychainStore(),
            audioCapture: audio,
            realtimeFactory: { _ in realtime },
            restClient: rest,
            permissionRequester: { true },
            notchOverlay: overlay,
            realtimeCompletionTimeoutNanos: 5_000_000_000,
            restTimeoutNanos: 5_000_000_000,
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
        await viewModel.stopAndWait()

        overlay.triggerCancel()
        try? await Task.sleep(nanoseconds: 1_000_000)

        XCTAssertEqual(viewModel.status, .idle)
        XCTAssertEqual(overlay.hideCount, 1)
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
        let settingsDefaults = UserDefaults(suiteName: UUID().uuidString)!
        let formattingSettings = FormattingSettingsStore(userDefaults: settingsDefaults)
        formattingSettings.isEnabled = false
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
            formattingSettings: formattingSettings,
        )

        viewModel.apiKeyInput = "sk-test"
        await viewModel.startAndWait()
        audio.emit(Data([0x01, 0x02]))
        await Task.yield()
        await viewModel.stopAndWait()

        realtime.emit(.inputAudioCommitted(.init(itemId: "item-1", previousItemId: nil)))
        realtime.emit(.transcriptionCompleted(.init(itemId: "item-1", contentIndex: 0, transcript: "Hello")))
        try? await Task.sleep(nanoseconds: 10_000_000)

        guard let insertIndex = injector.events.firstIndex(of: "insertFinal:Hello"),
              let finishIndex = injector.events.firstIndex(of: "finish")
        else {
            XCTFail("Expected insertFinal and finish events")
            return
        }
        XCTAssertLessThan(insertIndex, finishIndex)
    }

    func testFinalInsertHappensOnlyOnCompletedTranscript() async {
        let realtime = TestRealtimeClient()
        let audio = TestAudioCapture()
        let injector = TestDictationInjector()
        let settingsDefaults = UserDefaults(suiteName: UUID().uuidString)!
        let formattingSettings = FormattingSettingsStore(userDefaults: settingsDefaults)
        formattingSettings.isEnabled = false
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
            formattingSettings: formattingSettings,
        )

        viewModel.apiKeyInput = "sk-test"
        await viewModel.startAndWait()
        audio.emit(Data([0x01, 0x02]))
        await Task.yield()
        await viewModel.stopAndWait()

        realtime.emit(.inputAudioCommitted(.init(itemId: "item-1", previousItemId: nil)))
        realtime.emit(.transcriptionCompleted(.init(itemId: "item-1", contentIndex: 0, transcript: "Hello")))
        try? await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(injector.insertedTexts, ["Hello"])
        XCTAssertEqual(viewModel.lastFinalTranscript, "Hello")
    }

    func testPasteLastTranscriptCallsInsert() {
        let injector = TestDictationInjector()
        let viewModel = TranscriptionViewModel(
            keychain: InMemoryKeychainStore(),
            audioCapture: TestAudioCapture(),
            realtimeFactory: { _ in TestRealtimeClient() },
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

        viewModel.lastFinalTranscript = "Hello"
        viewModel.pasteLastTranscript()

        XCTAssertEqual(injector.insertedTexts, ["Hello"])
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
