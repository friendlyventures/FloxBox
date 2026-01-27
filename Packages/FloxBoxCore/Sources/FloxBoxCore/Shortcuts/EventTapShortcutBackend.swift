import CoreGraphics
import Foundation

protocol RetryTimer {
    func invalidate()
}

extension Timer: RetryTimer {}

@MainActor
public final class EventTapShortcutBackend: ShortcutBackend {
    typealias TapFactory = (CGEventMask, @escaping CGEventTapCallBack, UnsafeMutableRawPointer?) -> CFMachPort?
    typealias RunLoopSourceFactory = (CFMachPort) -> CFRunLoopSource
    typealias RetryTimerFactory = (TimeInterval, @escaping () -> Void) -> RetryTimer
    typealias ListenEventAccessChecker = () -> Bool
    typealias ListenEventAccessRequester = () -> Bool

    public var onTrigger: ((ShortcutTrigger) -> Void)?
    public var onStatusChange: ((String?) -> Void)?

    private var processor = ShortcutEventProcessor()
    private var shortcuts: [ShortcutDefinition] = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let runLoop: CFRunLoop?
    private let tapFactory: TapFactory
    private let runLoopSourceFactory: RunLoopSourceFactory
    private let retryTimerFactory: RetryTimerFactory
    private let listenEventAccessChecker: ListenEventAccessChecker
    private let listenEventAccessRequester: ListenEventAccessRequester
    private var retryTimer: RetryTimer?

    private var captureCompletion: ((ShortcutDefinition?) -> Void)?
    private var captureId: ShortcutID?
    private var captureBehavior: ShortcutBehavior = .pushToTalk
    private var captureName: String?
    private var captureCandidate: ShortcutDefinition?

    public convenience init() {
        self.init(
            tapFactory: EventTapShortcutBackend.defaultTapFactory,
            runLoop: CFRunLoopGetMain(),
            runLoopSourceFactory: EventTapShortcutBackend.defaultRunLoopSourceFactory,
            retryTimerFactory: EventTapShortcutBackend.defaultRetryTimerFactory,
            listenEventAccessChecker: EventTapShortcutBackend.defaultListenEventAccessChecker,
            listenEventAccessRequester: EventTapShortcutBackend.defaultListenEventAccessRequester,
        )
    }

    init(
        tapFactory: @escaping TapFactory,
        runLoop: CFRunLoop?,
        runLoopSourceFactory: @escaping RunLoopSourceFactory,
        retryTimerFactory: @escaping RetryTimerFactory,
        listenEventAccessChecker: @escaping ListenEventAccessChecker,
        listenEventAccessRequester: @escaping ListenEventAccessRequester,
    ) {
        self.tapFactory = tapFactory
        self.runLoop = runLoop
        self.runLoopSourceFactory = runLoopSourceFactory
        self.retryTimerFactory = retryTimerFactory
        self.listenEventAccessChecker = listenEventAccessChecker
        self.listenEventAccessRequester = listenEventAccessRequester
    }

    public func start() {
        ShortcutDebugLogger.log("backend.start")
        attemptStart()
    }

    private func attemptStart() {
        guard eventTap == nil else { return }

        if !listenEventAccessChecker() {
            onStatusChange?("Enable Input Monitoring for FloxBox in System Settings")
            ShortcutDebugLogger.log("backend.missingInputMonitoring")
            scheduleRetry()
            return
        }

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let backend = Unmanaged<EventTapShortcutBackend>.fromOpaque(refcon).takeUnretainedValue()
            return backend.handleEvent(proxy: proxy, type: type, event: event)
        }

        guard let eventTap = tapFactory(
            CGEventMask(mask),
            callback,
            Unmanaged.passUnretained(self).toOpaque(),
        ) else {
            onStatusChange?("Enable Input Monitoring for FloxBox in System Settings")
            ShortcutDebugLogger.log("backend.tapCreateFailed")
            scheduleRetry()
            return
        }

        let source = runLoopSourceFactory(eventTap)
        self.eventTap = eventTap
        runLoopSource = source
        if let runLoop {
            CFRunLoopAddSource(runLoop, source, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        clearRetryTimer()
        onStatusChange?(nil)
        ShortcutDebugLogger.log("backend.tapEnabled")
    }

    public func stop() {
        guard let runLoopSource, let eventTap, let runLoop else { return }
        CFRunLoopRemoveSource(runLoop, runLoopSource, .commonModes)
        CFMachPortInvalidate(eventTap)
        self.runLoopSource = nil
        self.eventTap = nil
        clearRetryTimer()
        ShortcutDebugLogger.log("backend.stop")
    }

    public func register(_ shortcuts: [ShortcutDefinition]) {
        self.shortcuts = shortcuts
    }

    public func beginCapture(for id: ShortcutID, completion: @escaping (ShortcutDefinition?) -> Void) {
        captureCompletion = completion
        captureId = id
        processor = ShortcutEventProcessor()
        captureBehavior = .pushToTalk
        captureName = name(for: id)
        captureCandidate = nil
    }

    private func handleEvent(proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent> {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let repeatFlag = event.getIntegerValueField(.keyboardEventAutorepeat)
        let tapLog = [
            "tap type=\(type.rawValue)",
            "key=\(keyCode)",
            "flags=\(event.flags.rawValue)",
            "repeat=\(repeatFlag)",
        ].joined(separator: " ")
        ShortcutDebugLogger.log(tapLog)
        guard let shortcutEvent = shortcutEvent(for: type, event: event) else {
            return Unmanaged.passUnretained(event)
        }

        let previousState = processor.currentState
        let triggers = processor.handle(shortcutEvent, shortcuts: shortcuts)
        let currentState = processor.currentState

        handleCapture(previousState: previousState, currentState: currentState)
        emitTriggers(triggers)

        let stateLog = [
            "state modifiers=\(currentState.modifiers.displayString)",
            "key=\(String(describing: currentState.pressedKeyCode))",
            "triggers=\(String(describing: triggers))",
        ].joined(separator: " ")
        ShortcutDebugLogger.log(stateLog)

        return Unmanaged.passUnretained(event)
    }

    private func shortcutEvent(for type: CGEventType, event: CGEvent) -> ShortcutEvent? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        switch type {
        case .keyDown:
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            return isRepeat ? nil : .keyDown(keyCode: keyCode)
        case .keyUp:
            return .keyUp(keyCode: keyCode)
        case .flagsChanged:
            let isDown = isModifierDown(keyCode: keyCode, flags: event.flags)
            return .flagsChanged(keyCode: keyCode, isDown: isDown)
        default:
            return nil
        }
    }

    private func handleCapture(previousState: ChordState, currentState: ChordState) {
        guard let captureId, let captureCompletion else { return }

        if !currentState.isEmpty {
            captureCandidate = ShortcutDefinition(
                id: captureId,
                name: captureName ?? "Shortcut",
                keyCode: currentState.pressedKeyCode,
                modifiers: currentState.modifiers,
                behavior: captureBehavior,
            )
        } else if !previousState.isEmpty, let candidate = captureCandidate {
            DispatchQueue.main.async {
                captureCompletion(candidate)
            }
            self.captureCompletion = nil
            self.captureId = nil
            captureCandidate = nil
        }
    }

    private func emitTriggers(_ triggers: [ShortcutTrigger]) {
        guard !triggers.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            triggers.forEach { self?.onTrigger?($0) }
        }
    }

    private func name(for id: ShortcutID) -> String {
        switch id {
        case .pushToTalk:
            "Push To Talk"
        }
    }

    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        retryTimer = retryTimerFactory(1.0) { [weak self] in
            self?.attemptStart()
        }
    }

    private func clearRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    private func isModifierDown(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        switch keyCode {
        case ModifierKeyCode.leftCommand, ModifierKeyCode.rightCommand:
            flags.contains(.maskCommand)
        case ModifierKeyCode.leftShift, ModifierKeyCode.rightShift:
            flags.contains(.maskShift)
        case ModifierKeyCode.leftOption, ModifierKeyCode.rightOption:
            flags.contains(.maskAlternate)
        case ModifierKeyCode.leftControl, ModifierKeyCode.rightControl:
            flags.contains(.maskControl)
        default:
            false
        }
    }
}

private extension EventTapShortcutBackend {
    static func defaultTapFactory(
        mask: CGEventMask,
        callback: @escaping CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer?,
    ) -> CFMachPort? {
        CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo,
        )
    }

    static func defaultRunLoopSourceFactory(_ eventTap: CFMachPort) -> CFRunLoopSource {
        CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    }

    static func defaultRetryTimerFactory(_ interval: TimeInterval, handler: @escaping () -> Void) -> RetryTimer {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            handler()
        }
    }

    static func defaultListenEventAccessChecker() -> Bool {
        CGPreflightListenEventAccess()
    }

    static func defaultListenEventAccessRequester() -> Bool {
        CGRequestListenEventAccess()
    }
}
