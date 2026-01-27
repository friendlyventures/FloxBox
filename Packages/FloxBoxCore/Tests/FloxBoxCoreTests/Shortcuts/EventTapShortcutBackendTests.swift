@testable import FloxBoxCore
import XCTest

@MainActor
final class EventTapShortcutBackendTests: XCTestCase {
    func testStartDoesNotRequestListenEventAccessWhenMissing() {
        var requestCount = 0
        var lastStatusMessage: String?

        let runLoopSourceFactory: EventTapShortcutBackend.RunLoopSourceFactory = { _ in
            var context = CFRunLoopSourceContext(
                version: 0,
                info: nil,
                retain: nil,
                release: nil,
                copyDescription: nil,
                equal: nil,
                hash: nil,
                schedule: nil,
                cancel: nil,
                perform: nil,
            )
            return CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)
        }

        let backend = EventTapShortcutBackend(
            tapFactory: { _, _, _ in nil },
            runLoop: CFRunLoopGetCurrent(),
            runLoopSourceFactory: runLoopSourceFactory,
            retryTimerFactory: { _, _ in TestRetryTimer(handler: {}) },
            listenEventAccessChecker: { false },
            listenEventAccessRequester: { requestCount += 1; return false },
        )
        backend.onStatusChange = { lastStatusMessage = $0 }

        backend.start()

        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(lastStatusMessage, "Enable Input Monitoring for FloxBox in System Settings")
    }

    func testStartRetriesUntilTapCreated() {
        var attempts = 0
        var lastStatusMessage: String?
        var capturedTimer: TestRetryTimer?

        let tapFactory: EventTapShortcutBackend.TapFactory = { _, _, _ in
            attempts += 1
            if attempts == 1 {
                return nil
            }
            return Self.makeMachPort()
        }

        let runLoopSourceFactory: EventTapShortcutBackend.RunLoopSourceFactory = { _ in
            var context = CFRunLoopSourceContext(
                version: 0,
                info: nil,
                retain: nil,
                release: nil,
                copyDescription: nil,
                equal: nil,
                hash: nil,
                schedule: nil,
                cancel: nil,
                perform: nil,
            )
            return CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)
        }

        let timerFactory: EventTapShortcutBackend.RetryTimerFactory = { _, handler in
            let timer = TestRetryTimer(handler: handler)
            capturedTimer = timer
            return timer
        }

        let backend = EventTapShortcutBackend(
            tapFactory: tapFactory,
            runLoop: CFRunLoopGetCurrent(),
            runLoopSourceFactory: runLoopSourceFactory,
            retryTimerFactory: timerFactory,
            listenEventAccessChecker: { true },
            listenEventAccessRequester: { true },
        )
        backend.onStatusChange = { lastStatusMessage = $0 }

        backend.start()

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(lastStatusMessage, "Enable Input Monitoring for FloxBox in System Settings")
        XCTAssertNotNil(capturedTimer)

        capturedTimer?.fire()

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(lastStatusMessage, nil)
    }

    private static func makeMachPort() -> CFMachPort {
        var shouldFree = DarwinBoolean(false)
        var context = CFMachPortContext(
            version: 0,
            info: nil,
            retain: nil,
            release: nil,
            copyDescription: nil,
        )
        return CFMachPortCreate(kCFAllocatorDefault, nil, &context, &shouldFree)
    }
}

private final class TestRetryTimer: RetryTimer {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func fire() {
        handler()
    }

    func invalidate() {}
}
