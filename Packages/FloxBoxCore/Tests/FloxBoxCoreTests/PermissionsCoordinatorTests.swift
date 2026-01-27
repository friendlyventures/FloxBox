@testable import FloxBoxCore
import XCTest

final class PermissionsCoordinatorTests: XCTestCase {
    @MainActor
    func testCoordinatorShowsWindowWhenMissing() async {
        let window = TestPermissionsWindow()
        let coordinator = PermissionsCoordinator(
            permissionChecker: { false },
            requestAccess: {},
            window: window,
        )

        await coordinator.refresh()

        XCTAssertEqual(window.showCount, 1)
    }

    @MainActor
    func testCoordinatorShowsWindowWhenAnyPermissionMissing() async {
        let window = TestPermissionsWindow()
        let coordinator = PermissionsCoordinator(
            permissionChecker: { false },
            requestAccess: {},
            window: window,
        )

        await coordinator.refresh()

        XCTAssertEqual(window.showCount, 1)
    }
}

@MainActor
private final class TestPermissionsWindow: PermissionsWindowPresenting {
    var showCount = 0
    func show() { showCount += 1 }
    func hide() {}
    func bringToFront() {}
}
