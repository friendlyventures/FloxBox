import Foundation
import Observation

@Observable
public final class PersonalGlossaryStore {
    public var entries: [PersonalGlossaryEntry] {
        didSet { persist() }
    }

    public var activeEntries: [PersonalGlossaryEntry] {
        entries.filter { entry in
            entry.isEnabled && !entry.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private let userDefaults: UserDefaults
    private let storageKey = "floxbox.glossary.v1"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([PersonalGlossaryEntry].self, from: data)
        {
            entries = decoded
        } else {
            entries = []
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}
