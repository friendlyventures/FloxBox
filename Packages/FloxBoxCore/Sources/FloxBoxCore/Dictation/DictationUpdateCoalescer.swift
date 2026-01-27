import Foundation

public protocol CoalescerTimer {
    func invalidate()
}

extension Timer: CoalescerTimer {}

public final class DictationUpdateCoalescer: DictationUpdateCoalescing {
    public typealias TimerFactory = (TimeInterval, @escaping () -> Void) -> CoalescerTimer

    private let interval: TimeInterval
    private let timerFactory: TimerFactory
    private var timer: CoalescerTimer?
    private var pendingText: String?
    private var pendingFlush: ((String) -> Void)?

    public init(
        interval: TimeInterval,
        timerFactory: @escaping TimerFactory = DictationUpdateCoalescer.defaultTimerFactory,
    ) {
        self.interval = interval
        self.timerFactory = timerFactory
    }

    public func enqueue(_ text: String, flush: @escaping (String) -> Void) {
        pendingText = text
        pendingFlush = flush
        guard timer == nil else { return }
        timer = timerFactory(interval) { [weak self] in
            self?.flushPending()
        }
    }

    public func flush() {
        flushPending()
    }

    public func cancel() {
        timer?.invalidate()
        timer = nil
        pendingText = nil
        pendingFlush = nil
    }

    private func flushPending() {
        guard let pending = pendingText, let flush = pendingFlush else { return }
        pendingText = nil
        pendingFlush = nil
        timer?.invalidate()
        timer = nil
        flush(pending)
    }

    public static func defaultTimerFactory(interval: TimeInterval, handler: @escaping () -> Void) -> CoalescerTimer {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            handler()
        }
    }
}
