@testable import FloxBoxCore
import XCTest

final class PermissionsViewTests: XCTestCase {
    @MainActor
    func testPermissionsViewBuildsWithNewRows() {
        let viewModel = PermissionsViewModel(
            inputMonitoringClient: .init(isGranted: { false }, requestAccess: { false }),
            accessibilityClient: .init(isTrusted: { false }, requestAccess: {}),
            microphoneClient: .init(authorizationStatus: { .denied }, requestAccess: { false }),
            settingsOpener: .init(open: {}),
        )

        _ = PermissionsView(viewModel: viewModel)
    }
}
