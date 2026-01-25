@testable import FloxBoxCore
import XCTest

@MainActor
final class ShortcutCoordinatorTests: XCTestCase {
    func testCoordinatorStartsAndStopsRecordingForPushToTalk() {
        let store = ShortcutStore(userDefaults: UserDefaults(suiteName: "ShortcutCoordinatorTests")!)
        store.upsert(ShortcutDefinition(
            id: .pushToTalk,
            name: "Push To Talk",
            keyCode: 49,
            modifiers: [.leftOption],
            behavior: .pushToTalk,
        ))

        let backend = FakeShortcutBackend()
        var started = 0
        var stopped = 0

        let coordinator = ShortcutCoordinator(
            store: store,
            backend: backend,
            actions: ShortcutActions(
                startRecording: { started += 1 },
                stopRecording: { stopped += 1 },
            ),
        )

        coordinator.start()
        backend.emit(.init(id: .pushToTalk, phase: .pressed))
        backend.emit(.init(id: .pushToTalk, phase: .released))

        XCTAssertEqual(started, 1)
        XCTAssertEqual(stopped, 1)
    }
}

private final class FakeShortcutBackend: ShortcutBackend {
    var onTrigger: ((ShortcutTrigger) -> Void)?

    func start() {}
    func stop() {}
    func register(_: [ShortcutDefinition]) {}
    func beginCapture(for _: ShortcutID, completion: @escaping (ShortcutDefinition?) -> Void) {
        completion(nil)
    }

    func emit(_ trigger: ShortcutTrigger) {
        onTrigger?(trigger)
    }
}
