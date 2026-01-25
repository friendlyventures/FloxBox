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
           let decoded = try? JSONDecoder().decode([ShortcutDefinition].self, from: data)
        {
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
