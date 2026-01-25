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
