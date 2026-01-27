@testable import FloxBoxCore
import XCTest

@MainActor
final class TranscriptionPermissionsTests: XCTestCase {
    func testStartBlockedWhenAccessibilityMissing() async {
        let overlay = TestNotchOverlay()
        let toast = TestToastPresenter()
        let injector = TestDictationInjector()
        let viewModel = TranscriptionViewModel(
            keychain: InMemoryKeychainStore(),
            audioCapture: TestAudioCapture(),
            realtimeFactory: { _ in TestRealtimeClient() },
            permissionRequester: { true },
            notchOverlay: overlay,
            toastPresenter: toast,
            accessibilityChecker: { false },
            secureInputChecker: { false },
            permissionsPresenter: {},
            dictationInjector: injector,
            clipboardWriter: { _ in },
        )
        viewModel.apiKeyInput = "sk-test"

        await viewModel.startAndWait()

        XCTAssertEqual(toast.toastMessages.last, "Accessibility permission required")
        XCTAssertEqual(injector.startCount, 0)
    }
}
