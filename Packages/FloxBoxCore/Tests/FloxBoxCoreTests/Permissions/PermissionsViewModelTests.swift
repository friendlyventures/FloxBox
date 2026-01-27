@testable import FloxBoxCore
import XCTest

final class PermissionsViewModelTests: XCTestCase {
    @MainActor
    func testAllRequiredGrantedRequiresInputMonitoringAccessibilityMicrophone() async {
        let input = InputMonitoringPermissionClient(
            isGranted: { true },
            requestAccess: { true },
        )
        let accessibility = AccessibilityPermissionClient(
            isTrusted: { true },
            requestAccess: {},
        )
        let microphone = MicrophonePermissionClient(
            authorizationStatus: { .authorized },
            requestAccess: { true },
        )
        let opener = SystemSettingsOpener(open: {})

        let viewModel = PermissionsViewModel(
            inputMonitoringClient: input,
            accessibilityClient: accessibility,
            microphoneClient: microphone,
            settingsOpener: opener,
        )

        await viewModel.refresh()

        XCTAssertTrue(viewModel.allGranted)
    }

    @MainActor
    func testRequestInputMonitoringOpensSettingsAndRefreshes() async {
        var requestCount = 0
        var openCount = 0

        let input = InputMonitoringPermissionClient(
            isGranted: { requestCount > 0 },
            requestAccess: { requestCount += 1; return true },
        )
        let accessibility = AccessibilityPermissionClient(
            isTrusted: { true },
            requestAccess: {},
        )
        let microphone = MicrophonePermissionClient(
            authorizationStatus: { .authorized },
            requestAccess: { true },
        )
        let opener = SystemSettingsOpener(open: { openCount += 1 })

        let viewModel = PermissionsViewModel(
            inputMonitoringClient: input,
            accessibilityClient: accessibility,
            microphoneClient: microphone,
            settingsOpener: opener,
        )

        await viewModel.requestInputMonitoringAccess()

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(openCount, 1)
        XCTAssertTrue(viewModel.inputMonitoringGranted)
    }
}
