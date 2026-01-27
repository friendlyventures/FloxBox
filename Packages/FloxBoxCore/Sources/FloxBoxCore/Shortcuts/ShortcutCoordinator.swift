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
    private var isStarted = false

    public init(store: ShortcutStore, backend: ShortcutBackend, actions: ShortcutActions) {
        self.store = store
        self.backend = backend
        self.actions = actions

        store.onUpdate = { [weak self] shortcuts in
            guard let self, isStarted else { return }
            backend.register(shortcuts)
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
        isStarted = true
        backend.register(store.shortcuts)
        backend.start()
    }

    public func stop() {
        backend.stop()
        isStarted = false
    }

    public func beginCapture(for id: ShortcutID, completion: @escaping (ShortcutDefinition?) -> Void) {
        backend.beginCapture(for: id, completion: completion)
    }

    private func handle(_ trigger: ShortcutTrigger) {
        switch trigger.phase {
        case .pressed:
            guard !isRecordingFromShortcut else { return }
            isRecordingFromShortcut = true
            ShortcutDebugLogger.log("shortcut pressed id=\(trigger.id.rawValue)")
            DebugLog
                .recording("shortcut.pressed id=\(trigger.id.rawValue) uptime=\(ProcessInfo.processInfo.systemUptime)")
            actions.startRecording()
        case .released:
            guard isRecordingFromShortcut else { return }
            isRecordingFromShortcut = false
            ShortcutDebugLogger.log("shortcut released id=\(trigger.id.rawValue)")
            DebugLog
                .recording("shortcut.released id=\(trigger.id.rawValue) uptime=\(ProcessInfo.processInfo.systemUptime)")
            actions.stopRecording()
        }
    }
}
