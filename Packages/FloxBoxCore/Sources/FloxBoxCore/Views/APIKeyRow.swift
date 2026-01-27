import SwiftUI

struct APIKeyRow: View {
    @Binding var apiKey: String
    @Binding var status: APIKeyStatus
    var onSave: () -> Void = {}

    var body: some View {
        ViewThatFits {
            HStack(spacing: 12) {
                TextField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 320)

                Button("Save") {
                    onSave()
                }

                if let message = status.message {
                    Text(message)
                        .foregroundStyle(statusColor(for: status))
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 12) {
                    Button("Save") {
                        onSave()
                    }

                    if let message = status.message {
                        Text(message)
                            .foregroundStyle(statusColor(for: status))
                    }
                }
            }
        }
    }

    private func statusColor(for status: APIKeyStatus) -> Color {
        switch status {
        case .error:
            .red
        default:
            .secondary
        }
    }
}
