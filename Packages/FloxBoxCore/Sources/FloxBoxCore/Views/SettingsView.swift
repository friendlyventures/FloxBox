import SwiftUI

public struct SettingsView: View {
    @Bindable var model: FloxBoxAppModel

    public init(model: FloxBoxAppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title2.weight(.semibold))
            APIKeyRow(
                apiKey: $model.viewModel.apiKeyInput,
                status: $model.viewModel.apiKeyStatus,
                onSave: model.viewModel.saveAPIKey,
            )
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 240)
    }
}
