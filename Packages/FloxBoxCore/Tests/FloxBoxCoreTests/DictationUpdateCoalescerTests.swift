@testable import FloxBoxCore
import XCTest

final class DictationUpdateCoalescerTests: XCTestCase {
    func testCoalescerEmitsLatestValueOnFire() {
        let timer = TestCoalescerTimer()
        let coalescer = DictationUpdateCoalescer(interval: 0.1, timerFactory: { _, handler in
            timer.handler = handler
            return timer
        })

        var flushed: [String] = []
        coalescer.enqueue("first") { flushed.append($0) }
        coalescer.enqueue("second") { flushed.append($0) }

        timer.fire()
        XCTAssertEqual(flushed, ["second"])
    }

    func testFlushEmitsPendingValue() {
        let timer = TestCoalescerTimer()
        let coalescer = DictationUpdateCoalescer(interval: 0.1, timerFactory: { _, handler in
            timer.handler = handler
            return timer
        })

        var flushed: [String] = []
        coalescer.enqueue("pending") { flushed.append($0) }

        coalescer.flush()
        XCTAssertEqual(flushed, ["pending"])
    }
}

private final class TestCoalescerTimer: CoalescerTimer {
    var handler: (() -> Void)?
    func invalidate() {}
    func fire() { handler?() }
}
