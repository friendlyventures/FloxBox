@testable import FloxBoxCore
import XCTest

@MainActor
final class FloxBoxAppModelTests: XCTestCase {
    func testStartInvokesCoordinatorStarts() {
        var permissionsStarted = false
        var shortcutsStarted = false

        let model = FloxBoxAppModel(
            configuration: .appStore,
            makePermissionsCoordinator: {
                TestCoordinator(onStart: { permissionsStarted = true })
            },
            makeShortcutCoordinator: {
                TestCoordinator(onStart: { shortcutsStarted = true })
            },
        )

        model.start()

        XCTAssertTrue(permissionsStarted)
        XCTAssertTrue(shortcutsStarted)
    }
}

private final class TestCoordinator: Coordinating {
    private let onStart: () -> Void

    init(onStart: @escaping () -> Void) {
        self.onStart = onStart
    }

    func start() {
        onStart()
    }

    func stop() {}
}
