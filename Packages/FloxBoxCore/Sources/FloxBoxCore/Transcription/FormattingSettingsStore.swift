import Foundation
import Observation

@Observable
public final class FormattingSettingsStore {
    private struct Snapshot: Codable {
        let isEnabled: Bool
        let model: FormattingModel
    }

    public var isEnabled: Bool {
        didSet { persist() }
    }

    public var model: FormattingModel {
        didSet { persist() }
    }

    private let userDefaults: UserDefaults
    private let storageKey = "floxbox.formatting.settings.v1"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(Snapshot.self, from: data)
        {
            isEnabled = decoded.isEnabled
            model = decoded.model
        } else {
            isEnabled = true
            model = .defaultModel
        }
    }

    private func persist() {
        let snapshot = Snapshot(isEnabled: isEnabled, model: model)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}
