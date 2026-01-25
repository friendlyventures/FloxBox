import Observation
import SwiftUI
import CoreAudio

public struct ContentView: View {
    private let configuration: FloxBoxDistributionConfiguration
    @State private var viewModel = TranscriptionViewModel()

    public init(configuration: FloxBoxDistributionConfiguration) {
        self.configuration = configuration
    }

    public var body: some View {
        @Bindable var viewModel = viewModel

        VStack(alignment: .leading, spacing: 12) {
            APIKeyRow(
                apiKey: $viewModel.apiKeyInput,
                status: $viewModel.apiKeyStatus,
                onSave: viewModel.saveAPIKey
            )

            HStack(spacing: 12) {
                Picker("Model", selection: $viewModel.model) {
                    ForEach(TranscriptionModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .frame(minWidth: 240)

                Picker("Language", selection: $viewModel.language) {
                    ForEach(TranscriptionLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .frame(minWidth: 180)

                Picker("Mic", selection: $viewModel.selectedInputDeviceID) {
                    Text("System Default").tag(AudioDeviceID?.none)
                    ForEach(viewModel.availableInputDevices) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
                .frame(minWidth: 220)
                .disabled(viewModel.isRecording)

                Picker("VAD Mode", selection: $viewModel.vadMode) {
                    ForEach(VADMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
            }

            if viewModel.vadMode == .off {
                Picker("Commit Interval", selection: $viewModel.manualCommitInterval) {
                    ForEach(ManualCommitInterval.options) { option in
                        Text(option.label).tag(option)
                    }
                }
                .frame(maxWidth: 240)
            }

            if viewModel.vadMode == .server {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Server VAD Tuning")
                        .font(.headline)

                    HStack(spacing: 12) {
                        OptionalDoubleField(title: "Threshold", value: $viewModel.serverVAD.threshold)
                        OptionalIntField(title: "Prefix Padding (ms)", value: $viewModel.serverVAD.prefixPaddingMs)
                        OptionalIntField(title: "Silence Duration (ms)", value: $viewModel.serverVAD.silenceDurationMs)
                        OptionalIntField(title: "Idle Timeout (ms)", value: $viewModel.serverVAD.idleTimeoutMs)
                    }
                }
            }

            HStack(spacing: 12) {
                Button(viewModel.isRecording ? "Stop" : "Start") {
                    viewModel.isRecording ? viewModel.stop() : viewModel.start()
                }
                .buttonStyle(.borderedProminent)

                Button("Clear") {
                    viewModel.clearTranscript()
                }

                Spacer()

                Text(viewModel.status.label)
                    .foregroundStyle(statusColor(for: viewModel.status))
            }

#if DEBUG
            if let error = viewModel.errorMessage {
                Text("Debug Error: \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
#endif

            TextEditor(text: $viewModel.transcript)
                .font(.body)
                .frame(minHeight: 320)

            Text(configuration.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            viewModel.refreshInputDevices()
        }
    }

    private func statusColor(for status: RecordingStatus) -> Color {
        if case .error = status {
            return .red
        }
        return .secondary
    }
}

struct APIKeyRow: View {
    @Binding var apiKey: String
    @Binding var status: APIKeyStatus
    var onSave: () -> Void = {}

    var body: some View {
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
    }

    private func statusColor(for status: APIKeyStatus) -> Color {
        switch status {
        case .error:
            return .red
        default:
            return .secondary
        }
    }
}

struct OptionalDoubleField: View {
    let title: String
    @Binding var value: Double?
    @State private var text: String

    init(title: String, value: Binding<Double?>) {
        self.title = title
        self._value = value
        self._text = State(initialValue: value.wrappedValue.map { String($0) } ?? "")
    }

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.roundedBorder)
            .onChange(of: text) { _, newValue in
                value = Double(newValue)
            }
    }
}

struct OptionalIntField: View {
    let title: String
    @Binding var value: Int?
    @State private var text: String

    init(title: String, value: Binding<Int?>) {
        self.title = title
        self._value = value
        self._text = State(initialValue: value.wrappedValue.map { String($0) } ?? "")
    }

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.roundedBorder)
            .onChange(of: text) { _, newValue in
                value = Int(newValue)
            }
    }
}
