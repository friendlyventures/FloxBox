# Global Shortcuts (Left/Right Modifiers) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a user-configurable, global push-to-talk shortcut with left/right modifier precision in direct builds, while structuring code for an App Store-compatible backend.

**Architecture:** Implement a shortcuts subsystem in FloxBoxCore with shared models + persistence, a pure event processor for left/right matching, and a pluggable backend. Direct builds use a CGEventTap backend and capture UI; App Store builds compile with a stub backend ready for future Carbon integration.

**Tech Stack:** Swift 6.2, SwiftUI, Observation (`@Observable`), CGEventTap (direct builds).

---

### Task 1: Core shortcut models + display formatting

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/ShortcutModels.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Shortcuts/ShortcutDefinitionTests.swift`

**Step 1: Write the failing test**

Create `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Shortcuts/ShortcutDefinitionTests.swift`:

```swift
@testable import FloxBoxCore
import XCTest

final class ShortcutDefinitionTests: XCTestCase {
    func testShortcutRoundTripKeepsLeftRightModifiers() throws {
        let shortcut = ShortcutDefinition(
            id: .pushToTalk,
            name: "Push To Talk",
            keyCode: 49,
            modifiers: [.leftOption, .rightCommand],
            behavior: .pushToTalk,
        )

        let data = try JSONEncoder().encode(shortcut)
        let decoded = try JSONDecoder().decode(ShortcutDefinition.self, from: data)

        XCTAssertEqual(decoded, shortcut)
    }

    func testDisplayStringIncludesModifierSidesAndKey() {
        let shortcut = ShortcutDefinition(
            id: .pushToTalk,
            name: "Push To Talk",
            keyCode: 49,
            modifiers: [.leftOption, .rightCommand],
            behavior: .pushToTalk,
        )

        XCTAssertEqual(shortcut.displayString, "⌥L ⌘R Space")
    }
}
```

**Step 2: Run test to verify it fails**

Run (from repo root):

```bash
cd Packages/FloxBoxCore
swift test --filter ShortcutDefinitionTests
```

Expected: FAIL with “cannot find type ‘ShortcutDefinition’ in scope”.

**Step 3: Write minimal implementation**

Create `Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/ShortcutModels.swift`:

```swift
import Foundation

public enum ShortcutID: String, Codable, CaseIterable, Sendable {
    case pushToTalk
}

public enum ShortcutBehavior: String, Codable, Sendable {
    case pushToTalk
    case toggle
}

public struct ModifierSet: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let leftShift = ModifierSet(rawValue: 1 << 0)
    public static let rightShift = ModifierSet(rawValue: 1 << 1)
    public static let leftControl = ModifierSet(rawValue: 1 << 2)
    public static let rightControl = ModifierSet(rawValue: 1 << 3)
    public static let leftOption = ModifierSet(rawValue: 1 << 4)
    public static let rightOption = ModifierSet(rawValue: 1 << 5)
    public static let leftCommand = ModifierSet(rawValue: 1 << 6)
    public static let rightCommand = ModifierSet(rawValue: 1 << 7)

    public var displayString: String {
        var parts: [String] = []
        if contains(.leftControl) { parts.append("⌃L") }
        if contains(.rightControl) { parts.append("⌃R") }
        if contains(.leftOption) { parts.append("⌥L") }
        if contains(.rightOption) { parts.append("⌥R") }
        if contains(.leftShift) { parts.append("⇧L") }
        if contains(.rightShift) { parts.append("⇧R") }
        if contains(.leftCommand) { parts.append("⌘L") }
        if contains(.rightCommand) { parts.append("⌘R") }
        return parts.joined(separator: " ")
    }
}

public struct ShortcutDefinition: Codable, Hashable, Identifiable, Sendable {
    public let id: ShortcutID
    public var name: String
    public var keyCode: UInt16?
    public var modifiers: ModifierSet
    public var behavior: ShortcutBehavior

    public init(
        id: ShortcutID,
        name: String,
        keyCode: UInt16?,
        modifiers: ModifierSet,
        behavior: ShortcutBehavior,
    ) {
        self.id = id
        self.name = name
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.behavior = behavior
    }

    public var isEmpty: Bool {
        keyCode == nil && modifiers.isEmpty
    }

    public var displayString: String {
        let key = keyCode.map(KeyCodeDisplay.name(for:)) ?? ""
        let parts = [modifiers.displayString, key].filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }
}

private enum KeyCodeDisplay {
    static func name(for keyCode: UInt16) -> String {
        switch keyCode {
        case 49:
            return "Space"
        case 36:
            return "Return"
        case 53:
            return "Escape"
        default:
            return "Key \(keyCode)"
        }
    }
}
```

**Step 4: Run test to verify it passes**

```bash
cd Packages/FloxBoxCore
swift test --filter ShortcutDefinitionTests
```

Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/ShortcutModels.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Shortcuts/ShortcutDefinitionTests.swift
git commit -m "feat: add shortcut models and display formatting"
```

---

### Task 2: ShortcutStore persistence + validation

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/ShortcutStore.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Shortcuts/ShortcutStoreTests.swift`

**Step 1: Write the failing test**

Create `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Shortcuts/ShortcutStoreTests.swift`:

```swift
@testable import FloxBoxCore
import XCTest

final class ShortcutStoreTests: XCTestCase {
    func testUpsertReplacesExistingShortcut() {
        let store = ShortcutStore(userDefaults: UserDefaults(suiteName: "ShortcutStoreTests")!)
        let original = ShortcutDefinition(
            id: .pushToTalk,
            name: "Push To Talk",
            keyCode: 49,
            modifiers: [.leftOption],
            behavior: .pushToTalk,
        )
        let updated = ShortcutDefinition(
            id: .pushToTalk,
            name: "Push To Talk",
            keyCode: 49,
            modifiers: [.rightCommand],
            behavior: .pushToTalk,
        )

        store.upsert(original)
        store.upsert(updated)

        XCTAssertEqual(store.shortcuts.count, 1)
        XCTAssertEqual(store.shortcut(for: .pushToTalk), updated)
    }

    func testPersistenceRoundTrip() throws {
        let suite = "ShortcutStoreTestsRoundTrip"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let shortcut = ShortcutDefinition(
            id: .pushToTalk,
            name: "Push To Talk",
            keyCode: 49,
            modifiers: [.leftOption, .rightCommand],
            behavior: .pushToTalk,
        )

        let store = ShortcutStore(userDefaults: defaults)
        store.upsert(shortcut)

        let reloaded = ShortcutStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.shortcut(for: .pushToTalk), shortcut)
    }
}
```

**Step 2: Run test to verify it fails**

```bash
cd Packages/FloxBoxCore
swift test --filter ShortcutStoreTests
```

Expected: FAIL with “cannot find type ‘ShortcutStore’ in scope”.

**Step 3: Write minimal implementation**

Create `Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/ShortcutStore.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
public final class ShortcutStore {
    public var shortcuts: [ShortcutDefinition] {
        didSet {
            persist()
            onUpdate?(shortcuts)
        }
    }

    public var lastError: String?
    public var onUpdate: (([ShortcutDefinition]) -> Void)?

    private let userDefaults: UserDefaults
    private let storageKey = "floxbox.shortcuts.v1"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ShortcutDefinition].self, from: data) {
            shortcuts = decoded
        } else {
            shortcuts = []
        }
    }

    public func shortcut(for id: ShortcutID) -> ShortcutDefinition? {
        shortcuts.first { $0.id == id }
    }

    public func upsert(_ shortcut: ShortcutDefinition) {
        guard !shortcut.isEmpty else {
            lastError = "Shortcut cannot be empty"
            return
        }

        lastError = nil
        shortcuts.removeAll { $0.id == shortcut.id }
        shortcuts.append(shortcut)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(shortcuts) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}
```

**Step 4: Run test to verify it passes**

```bash
cd Packages/FloxBoxCore
swift test --filter ShortcutStoreTests
```

Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/ShortcutStore.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Shortcuts/ShortcutStoreTests.swift
git commit -m "feat: add shortcut store persistence"
```

---

### Task 3: Event processing + left/right matching

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/ShortcutEventProcessing.swift`
- Test: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Shortcuts/ShortcutEventProcessingTests.swift`

**Step 1: Write the failing test**

Create `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Shortcuts/ShortcutEventProcessingTests.swift`:

```swift
@testable import FloxBoxCore
import XCTest

final class ShortcutEventProcessingTests: XCTestCase {
    func testModifierOnlyShortcutTriggersOnPressAndRelease() {
        var processor = ShortcutEventProcessor()
        let shortcut = ShortcutDefinition(
            id: .pushToTalk,
            name: "Push To Talk",
            keyCode: nil,
            modifiers: [.rightCommand],
            behavior: .pushToTalk,
        )

        let press = processor.handle(.flagsChanged(keyCode: ModifierKeyCode.rightCommand), shortcuts: [shortcut])
        XCTAssertEqual(press, [ShortcutTrigger(id: .pushToTalk, phase: .pressed)])

        let release = processor.handle(.flagsChanged(keyCode: ModifierKeyCode.rightCommand), shortcuts: [shortcut])
        XCTAssertEqual(release, [ShortcutTrigger(id: .pushToTalk, phase: .released)])
    }

    func testChordShortcutTriggersOnKeyDownAndKeyUp() {
        var processor = ShortcutEventProcessor()
        let shortcut = ShortcutDefinition(
            id: .pushToTalk,
            name: "Push To Talk",
            keyCode: 49,
            modifiers: [.leftOption],
            behavior: .pushToTalk,
        )

        _ = processor.handle(.flagsChanged(keyCode: ModifierKeyCode.leftOption), shortcuts: [shortcut])
        let press = processor.handle(.keyDown(keyCode: 49), shortcuts: [shortcut])
        XCTAssertEqual(press, [ShortcutTrigger(id: .pushToTalk, phase: .pressed)])

        let release = processor.handle(.keyUp(keyCode: 49), shortcuts: [shortcut])
        XCTAssertEqual(release, [ShortcutTrigger(id: .pushToTalk, phase: .released)])
    }
}
```

**Step 2: Run test to verify it fails**

```bash
cd Packages/FloxBoxCore
swift test --filter ShortcutEventProcessingTests
```

Expected: FAIL with “cannot find type ‘ShortcutEventProcessor’ in scope”.

**Step 3: Write minimal implementation**

Create `Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/ShortcutEventProcessing.swift`:

```swift
import Foundation

public enum ShortcutEvent: Equatable {
    case keyDown(keyCode: UInt16)
    case keyUp(keyCode: UInt16)
    case flagsChanged(keyCode: UInt16)
}

public enum ShortcutTriggerPhase: Equatable {
    case pressed
    case released
}

public struct ShortcutTrigger: Equatable {
    public let id: ShortcutID
    public let phase: ShortcutTriggerPhase
}

public enum ModifierKeyCode {
    public static let leftShift: UInt16 = 56
    public static let rightShift: UInt16 = 60
    public static let leftControl: UInt16 = 59
    public static let rightControl: UInt16 = 62
    public static let leftOption: UInt16 = 58
    public static let rightOption: UInt16 = 61
    public static let leftCommand: UInt16 = 55
    public static let rightCommand: UInt16 = 54

    public static func modifier(for keyCode: UInt16) -> ModifierSet? {
        switch keyCode {
        case leftShift: return .leftShift
        case rightShift: return .rightShift
        case leftControl: return .leftControl
        case rightControl: return .rightControl
        case leftOption: return .leftOption
        case rightOption: return .rightOption
        case leftCommand: return .leftCommand
        case rightCommand: return .rightCommand
        default: return nil
        }
    }
}

struct ChordState: Equatable {
    var modifiers: ModifierSet = []
    var pressedKeyCode: UInt16?

    var isEmpty: Bool {
        pressedKeyCode == nil && modifiers.isEmpty
    }

    mutating func apply(_ event: ShortcutEvent) {
        switch event {
        case let .flagsChanged(keyCode):
            guard let modifier = ModifierKeyCode.modifier(for: keyCode) else { return }
            if modifiers.contains(modifier) {
                modifiers.remove(modifier)
            } else {
                modifiers.insert(modifier)
            }
        case let .keyDown(keyCode):
            pressedKeyCode = keyCode
        case let .keyUp(keyCode):
            if pressedKeyCode == keyCode {
                pressedKeyCode = nil
            }
        }
    }
}

public struct ShortcutEventProcessor {
    private var state = ChordState()
    private var activeShortcuts: Set<ShortcutID> = []

    public init() {}

    var currentState: ChordState { state }

    public mutating func handle(_ event: ShortcutEvent, shortcuts: [ShortcutDefinition]) -> [ShortcutTrigger] {
        state.apply(event)

        let currentlyActive = Set(shortcuts.filter { matches($0) }.map(\.id))
        let pressed = currentlyActive.subtracting(activeShortcuts)
        let released = activeShortcuts.subtracting(currentlyActive)

        activeShortcuts = currentlyActive

        return pressed.map { ShortcutTrigger(id: $0, phase: .pressed) }
            + released.map { ShortcutTrigger(id: $0, phase: .released) }
    }

    private func matches(_ shortcut: ShortcutDefinition) -> Bool {
        if shortcut.modifiers != state.modifiers { return false }
        switch shortcut.keyCode {
        case nil:
            return state.pressedKeyCode == nil
        case let keyCode:
            return state.pressedKeyCode == keyCode
        }
    }
}
```

**Step 4: Run test to verify it passes**

```bash
cd Packages/FloxBoxCore
swift test --filter ShortcutEventProcessingTests
```

Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/ShortcutEventProcessing.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Shortcuts/ShortcutEventProcessingTests.swift
git commit -m "feat: add shortcut event processing and matching"
```

---

### Task 4: Shortcut backend protocol + EventTap backend

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/ShortcutBackend.swift`
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/EventTapShortcutBackend.swift`

**Step 1: Write the failing test**

Create `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Shortcuts/ShortcutCoordinatorTests.swift` with a fake backend (the test will fail until the protocol exists):

```swift
@testable import FloxBoxCore
import XCTest

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
                stopRecording: { stopped += 1 }
            )
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
    func register(_ shortcuts: [ShortcutDefinition]) {}
    func beginCapture(for id: ShortcutID, completion: @escaping (ShortcutDefinition?) -> Void) {
        completion(nil)
    }

    func emit(_ trigger: ShortcutTrigger) {
        onTrigger?(trigger)
    }
}
```

**Step 2: Run test to verify it fails**

```bash
cd Packages/FloxBoxCore
swift test --filter ShortcutCoordinatorTests
```

Expected: FAIL with “cannot find type ‘ShortcutBackend’ in scope”.

**Step 3: Write minimal implementation**

Create `Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/ShortcutBackend.swift`:

```swift
import Foundation

@MainActor
public protocol ShortcutBackend: AnyObject {
    var onTrigger: ((ShortcutTrigger) -> Void)? { get set }

    func start()
    func stop()
    func register(_ shortcuts: [ShortcutDefinition])
    func beginCapture(for id: ShortcutID, completion: @escaping (ShortcutDefinition?) -> Void)
}
```

Create `Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/EventTapShortcutBackend.swift`:

```swift
import Foundation
import CoreGraphics

@MainActor
public final class EventTapShortcutBackend: ShortcutBackend {
    public var onTrigger: ((ShortcutTrigger) -> Void)?
    public var onStatusChange: ((String?) -> Void)?

    private var processor = ShortcutEventProcessor()
    private var shortcuts: [ShortcutDefinition] = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    private var captureCompletion: ((ShortcutDefinition?) -> Void)?
    private var captureId: ShortcutID?
    private var captureBehavior: ShortcutBehavior = .pushToTalk
    private var captureName: String?
    private var captureCandidate: ShortcutDefinition?

    public init() {}

    public func start() {
        guard thread == nil else { return }
        let thread = Thread { [weak self] in
            self?.runLoopStart()
        }
        self.thread = thread
        thread.start()
    }

    public func stop() {
        guard let runLoopSource, let eventTap, let runLoop else { return }
        CFRunLoopRemoveSource(runLoop, runLoopSource, .commonModes)
        CFMachPortInvalidate(eventTap)
        CFRunLoopStop(runLoop)
        self.runLoopSource = nil
        self.eventTap = nil
        self.runLoop = nil
        thread?.cancel()
        thread = nil
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

    private func runLoopStart() {
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
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            DispatchQueue.main.async { [weak self] in
                self?.onStatusChange?("Enable Input Monitoring for FloxBox in System Settings")
            }
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.eventTap = eventTap
        self.runLoopSource = source
        self.runLoop = CFRunLoopGetCurrent()

        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        CFRunLoopRun()
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent> {
        switch type {
        case .keyDown, .keyUp, .flagsChanged:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let shortcutEvent: ShortcutEvent

            switch type {
            case .keyDown:
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                if isRepeat { return Unmanaged.passUnretained(event) }
                shortcutEvent = .keyDown(keyCode: keyCode)
            case .keyUp:
                shortcutEvent = .keyUp(keyCode: keyCode)
            case .flagsChanged:
                shortcutEvent = .flagsChanged(keyCode: keyCode)
            default:
                return Unmanaged.passUnretained(event)
            }

            let previousState = processor.currentState
            let triggers = processor.handle(shortcutEvent, shortcuts: shortcuts)
            let currentState = processor.currentState

            if let captureId, let captureCompletion {
                if !currentState.isEmpty {
                    captureCandidate = ShortcutDefinition(
                        id: captureId,
                        name: captureName ?? \"Shortcut\",
                        keyCode: currentState.pressedKeyCode,
                        modifiers: currentState.modifiers,
                        behavior: captureBehavior
                    )
                } else if !previousState.isEmpty, let candidate = captureCandidate {
                    DispatchQueue.main.async {
                        captureCompletion(candidate)
                    }
                    self.captureCompletion = nil
                    self.captureId = nil
                    self.captureCandidate = nil
                }
            }

            if !triggers.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    triggers.forEach { self?.onTrigger?($0) }
                }
            }
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func name(for id: ShortcutID) -> String {
        switch id {
        case .pushToTalk:
            return \"Push To Talk\"
        }
    }
}
```

**Step 4: Run test to verify it passes**

```bash
cd Packages/FloxBoxCore
swift test --filter ShortcutCoordinatorTests
```

Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/ShortcutBackend.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/EventTapShortcutBackend.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Shortcuts/ShortcutCoordinatorTests.swift
git commit -m "feat: add shortcut backend protocol and event tap backend"
```

---

### Task 5: Shortcut coordinator + App Store stub backend

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/ShortcutCoordinator.swift`
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/AppStoreShortcutBackend.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Shortcuts/ShortcutCoordinatorTests.swift`

**Step 1: Write the failing test**

Extend `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Shortcuts/ShortcutCoordinatorTests.swift`:

```swift
func testCoordinatorUsesStoreUpdatesToRegisterShortcuts() {
    let store = ShortcutStore(userDefaults: UserDefaults(suiteName: "ShortcutCoordinatorTests")!)
    let backend = FakeShortcutBackend()
    let coordinator = ShortcutCoordinator(
        store: store,
        backend: backend,
        actions: ShortcutActions(startRecording: {}, stopRecording: {})
    )

    coordinator.start()
    store.upsert(ShortcutDefinition(
        id: .pushToTalk,
        name: "Push To Talk",
        keyCode: 49,
        modifiers: [.leftOption],
        behavior: .pushToTalk
    ))

    XCTAssertEqual(backend.registered.count, 1)
}
```

Update `FakeShortcutBackend` to record registrations:

```swift
private final class FakeShortcutBackend: ShortcutBackend {
    var onTrigger: ((ShortcutTrigger) -> Void)?
    var registered: [ShortcutDefinition] = []

    func start() {}
    func stop() {}
    func register(_ shortcuts: [ShortcutDefinition]) { registered = shortcuts }
    func beginCapture(for id: ShortcutID, completion: @escaping (ShortcutDefinition?) -> Void) { completion(nil) }

    func emit(_ trigger: ShortcutTrigger) { onTrigger?(trigger) }
}
```

**Step 2: Run test to verify it fails**

```bash
cd Packages/FloxBoxCore
swift test --filter ShortcutCoordinatorTests
```

Expected: FAIL with “cannot find type ‘ShortcutCoordinator’ in scope”.

**Step 3: Write minimal implementation**

Create `Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/ShortcutCoordinator.swift`:

```swift
import Foundation
import Observation

public struct ShortcutActions {
    public let startRecording: () -> Void
    public let stopRecording: () -> Void

    public init(startRecording: @escaping () -> Void, stopRecording: @escaping () -> Void) {
        self.startRecording = startRecording
        self.stopRecording = stopRecording
    }
}

@MainActor
@Observable
public final class ShortcutCoordinator {
    public var statusMessage: String?

    private let store: ShortcutStore
    private let backend: ShortcutBackend
    private let actions: ShortcutActions
    private var isRecordingFromShortcut = false

    public init(store: ShortcutStore, backend: ShortcutBackend, actions: ShortcutActions) {
        self.store = store
        self.backend = backend
        self.actions = actions

        store.onUpdate = { [weak self] shortcuts in
            self?.backend.register(shortcuts)
        }

        backend.onTrigger = { [weak self] trigger in
            self?.handle(trigger)
        }
    }

    public convenience init(store: ShortcutStore, actions: ShortcutActions) {
        #if APP_STORE
        let backend: ShortcutBackend = AppStoreShortcutBackend()
        #else
        let backend: ShortcutBackend = EventTapShortcutBackend()
        #endif
        self.init(store: store, backend: backend, actions: actions)
    }

    public func start() {
        backend.register(store.shortcuts)
        backend.start()
    }

    public func stop() {
        backend.stop()
    }

    public func beginCapture(for id: ShortcutID, completion: @escaping (ShortcutDefinition?) -> Void) {
        backend.beginCapture(for: id, completion: completion)
    }

    private func handle(_ trigger: ShortcutTrigger) {
        switch trigger.phase {
        case .pressed:
            guard !isRecordingFromShortcut else { return }
            isRecordingFromShortcut = true
            actions.startRecording()
        case .released:
            guard isRecordingFromShortcut else { return }
            isRecordingFromShortcut = false
            actions.stopRecording()
        }
    }
}
```

Create `Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/AppStoreShortcutBackend.swift`:

```swift
import Foundation

@MainActor
public final class AppStoreShortcutBackend: ShortcutBackend {
    public var onTrigger: ((ShortcutTrigger) -> Void)?

    public init() {}

    public func start() {}
    public func stop() {}
    public func register(_ shortcuts: [ShortcutDefinition]) {}
    public func beginCapture(for id: ShortcutID, completion: @escaping (ShortcutDefinition?) -> Void) {
        completion(nil)
    }
}
```

**Step 4: Run test to verify it passes**

```bash
cd Packages/FloxBoxCore
swift test --filter ShortcutCoordinatorTests
```

Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/ShortcutCoordinator.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/AppStoreShortcutBackend.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/Shortcuts/ShortcutCoordinatorTests.swift
git commit -m "feat: add shortcut coordinator and app store backend stub"
```

---

### Task 6: Recorder UI + ContentView integration

**Files:**
- Create: `Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/ShortcutRecorderView.swift`
- Modify: `Packages/FloxBoxCore/Sources/FloxBoxCore/Views/ContentView.swift`
- Modify: `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/ContentViewTests.swift`

**Step 1: Write the failing test**

Update `Packages/FloxBoxCore/Tests/FloxBoxCoreTests/ContentViewTests.swift`:

```swift
@MainActor
final class ContentViewTests: XCTestCase {
    func testContentViewBuildsWithAPIKeyRow() {
        _ = ContentView(configuration: .appStore)
        _ = APIKeyRow(apiKey: .constant(""), status: .constant(.idle))
    }

    func testContentViewBuildsWithShortcutRecorder() {
        _ = ContentView(configuration: .appStore)
    }
}
```

**Step 2: Run test to verify it fails**

```bash
cd Packages/FloxBoxCore
swift test --filter ContentViewTests
```

Expected: FAIL with “cannot find type ‘ShortcutRecorderView’ in scope”.

**Step 3: Write minimal implementation**

Create `Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/ShortcutRecorderView.swift`:

```swift
import SwiftUI

public struct ShortcutRecorderView: View {
    @Bindable private var store: ShortcutStore
    private let coordinator: ShortcutCoordinator
    @State private var isRecording = false

    public init(store: ShortcutStore, coordinator: ShortcutCoordinator) {
        self.store = store
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Push To Talk")
                Spacer()
                Text(store.shortcut(for: .pushToTalk)?.displayString ?? "Not set")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button(isRecording ? "Cancel" : "Record") {
                    if isRecording {
                        isRecording = false
                    } else {
                        isRecording = true
                        coordinator.beginCapture(for: .pushToTalk) { shortcut in
                            isRecording = false
                            guard let shortcut else { return }
                            store.upsert(shortcut)
                        }
                    }
                }
                .buttonStyle(.bordered)

                if let message = store.lastError {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}
```

Modify `Packages/FloxBoxCore/Sources/FloxBoxCore/Views/ContentView.swift` (add properties + UI):

```swift
@State private var shortcutStore = ShortcutStore()
@State private var shortcutCoordinator: ShortcutCoordinator?
```

Inside `sectionCard("Session")` or directly below it add:

```swift
sectionCard("Shortcuts") {
    if let shortcutCoordinator {
        ShortcutRecorderView(store: shortcutStore, coordinator: shortcutCoordinator)
    }
}
```

And in `.onAppear`:

```swift
.onAppear {
    viewModel.refreshInputDevices()
    configuration.onAppear?()

    if shortcutCoordinator == nil {
        shortcutCoordinator = ShortcutCoordinator(
            store: shortcutStore,
            actions: ShortcutActions(
                startRecording: { viewModel.start() },
                stopRecording: { viewModel.stop() }
            )
        )
    }
    shortcutCoordinator?.start()
}
.onDisappear {
    shortcutCoordinator?.stop()
}
```

**Step 4: Run test to verify it passes**

```bash
cd Packages/FloxBoxCore
swift test --filter ContentViewTests
```

Expected: PASS.

**Step 5: Commit**

```bash
git add Packages/FloxBoxCore/Sources/FloxBoxCore/Shortcuts/ShortcutRecorderView.swift \
  Packages/FloxBoxCore/Sources/FloxBoxCore/Views/ContentView.swift \
  Packages/FloxBoxCore/Tests/FloxBoxCoreTests/ContentViewTests.swift
git commit -m "feat: add shortcut recorder UI"
```

---

### Task 7: Full test pass

**Files:**
- None

**Step 1: Run full test suite**

```bash
cd Packages/FloxBoxCore
swift test
```

Expected: PASS (with integration tests skipped unless FLOXBOX_RUN_INTEGRATION_TESTS=1).

**Step 2: Commit test run note (optional)**

No code changes expected. If `Package.resolved` appears, remove it before committing.
