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

            GroupBox("Formatting") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Post-process final transcript", isOn: $model.formattingSettings.isEnabled)

                    Picker("Model", selection: $model.formattingSettings.model) {
                        ForEach(FormattingModel.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("Formatting runs after recording to clean punctuation and apply your glossary.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GlossaryEditorView(store: model.glossaryStore)
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 520)
    }
}
