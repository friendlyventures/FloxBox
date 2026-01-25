import CoreGraphics
import Foundation

@MainActor
public final class EventTapShortcutBackend: ShortcutBackend {
    public var onTrigger: ((ShortcutTrigger) -> Void)?
    public var onStatusChange: ((String?) -> Void)?

    private var processor = ShortcutEventProcessor()
    private var shortcuts: [ShortcutDefinition] = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?

    private var captureCompletion: ((ShortcutDefinition?) -> Void)?
    private var captureId: ShortcutID?
    private var captureBehavior: ShortcutBehavior = .pushToTalk
    private var captureName: String?
    private var captureCandidate: ShortcutDefinition?

    public init() {}

    public func start() {
        guard eventTap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let backend = Unmanaged<EventTapShortcutBackend>.fromOpaque(refcon).takeUnretainedValue()
            return backend.handleEvent(proxy: proxy, type: type, event: event)
        }

        let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque(),
        )

        guard let eventTap else {
            DispatchQueue.main.async { [weak self] in
                self?.onStatusChange?("Enable Input Monitoring for FloxBox in System Settings")
            }
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.eventTap = eventTap
        runLoopSource = source
        runLoop = CFRunLoopGetMain()

        if let runLoop {
            CFRunLoopAddSource(runLoop, source, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    public func stop() {
        guard let runLoopSource, let eventTap, let runLoop else { return }
        CFRunLoopRemoveSource(runLoop, runLoopSource, .commonModes)
        CFMachPortInvalidate(eventTap)
        self.runLoopSource = nil
        self.eventTap = nil
        self.runLoop = nil
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
        guard let shortcutEvent = shortcutEvent(for: type, event: event) else {
            return Unmanaged.passUnretained(event)
        }

        let previousState = processor.currentState
        let triggers = processor.handle(shortcutEvent, shortcuts: shortcuts)
        let currentState = processor.currentState

        handleCapture(previousState: previousState, currentState: currentState)
        emitTriggers(triggers)

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
            return .flagsChanged(keyCode: keyCode)
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
}
