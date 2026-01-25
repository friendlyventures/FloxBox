import SwiftUI

struct UpdatesView: View {
    @ObservedObject var updaterController: UpdaterController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button("Check for Updates") {
                    updaterController.checkForUpdates()
                }
                .disabled(!updaterController.canCheckForUpdates)

                Text(lastCheckLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            Toggle(
                "Check for updates automatically",
                isOn: Binding(
                    get: { updaterController.automaticallyChecksForUpdates },
                    set: { enabled in
                        updaterController.setAutomaticallyChecksForUpdates(enabled)
                    },
                ),
            )
        }
    }

    private var lastCheckLabel: String {
        if let lastCheck = updaterController.lastUpdateCheckDate {
            return "Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Last checked: Never"
    }
}
