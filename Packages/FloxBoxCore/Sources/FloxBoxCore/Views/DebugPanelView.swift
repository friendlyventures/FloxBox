import CoreAudio
import Observation
import SwiftUI

public struct DebugPanelView: View {
    public let model: FloxBoxAppModel
    @State private var updatesExpanded = false
    @State private var serverVADExpanded = false
    private let tuningColumns = [GridItem(.adaptive(minimum: 200), spacing: 12)]

    public init(model: FloxBoxAppModel) {
        self.model = model
    }

    public var body: some View {
        @Bindable var viewModel = model.viewModel

        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FloxBox")
                        .font(.title2.weight(.semibold))
                    Text(model.configuration.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(viewModel.status.label)
                    .font(.headline)
                    .foregroundStyle(statusColor(for: viewModel.status))
            }

            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionCard("Session") {
                            VStack(alignment: .leading, spacing: 12) {
                                APIKeyRow(
                                    apiKey: $viewModel.apiKeyInput,
                                    status: $viewModel.apiKeyStatus,
                                    onSave: viewModel.saveAPIKey,
                                )
                                .controlSize(.large)

                                Divider()

                                HStack(spacing: 12) {
                                    Button(viewModel.isRecording ? "Stop" : "Start") {
                                        if viewModel.isRecording {
                                            Task { await viewModel.stopAndWait() }
                                        } else {
                                            viewModel.start()
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button("Clear") {
                                        viewModel.clearTranscript()
                                    }

                                    Spacer()
                                }

                                #if DEBUG
                                    if let error = viewModel.errorMessage {
                                        Text("Debug Error: \(error)")
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                    }
                                #endif
                            }
                        }

                        sectionCard("Shortcuts") {
                            if let shortcutCoordinator = model.shortcutCoordinator {
                                ShortcutRecorderView(
                                    store: model.shortcutStore,
                                    coordinator: shortcutCoordinator,
                                )
                            }
                        }

                        if let updatesView = model.configuration.updatesView {
                            DisclosureGroup(
                                isExpanded: $updatesExpanded,
                                content: {
                                    updatesView
                                        .padding(.top, 8)
                                },
                                label: {
                                    HStack {
                                        Text("Updates")
                                            .font(.headline)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.snappy(duration: 0.2)) {
                                            updatesExpanded.toggle()
                                        }
                                    }
                                },
                            )
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .animation(.snappy(duration: 0.2), value: updatesExpanded)
                        }

                        sectionCard("Configuration") {
                            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                                GridRow {
                                    LabeledContent("Model") {
                                        Picker("Model", selection: $viewModel.model) {
                                            ForEach(TranscriptionModel.allCases) { model in
                                                Text(model.displayName).tag(model)
                                            }
                                        }
                                        .labelsHidden()
                                    }
                                }

                                GridRow {
                                    LabeledContent("Language") {
                                        Picker("Language", selection: $viewModel.language) {
                                            ForEach(TranscriptionLanguage.allCases) { language in
                                                Text(language.displayName).tag(language)
                                            }
                                        }
                                        .labelsHidden()
                                    }
                                }

                                GridRow {
                                    LabeledContent("Noise Reduction") {
                                        Picker("Noise Reduction", selection: $viewModel.noiseReduction) {
                                            ForEach(NoiseReductionOption.allCases) { option in
                                                Text(option.displayName).tag(option)
                                            }
                                        }
                                        .labelsHidden()
                                    }
                                }

                                GridRow {
                                    LabeledContent("Mic") {
                                        Picker("Mic", selection: $viewModel.selectedInputDeviceID) {
                                            Text("System Default").tag(AudioDeviceID?.none)
                                            ForEach(viewModel.availableInputDevices) { device in
                                                Text(device.name).tag(Optional(device.id))
                                            }
                                        }
                                        .labelsHidden()
                                        .disabled(viewModel.isRecording)
                                    }
                                }

                                GridRow {
                                    LabeledContent("VAD Mode") {
                                        Picker("", selection: $viewModel.vadMode) {
                                            ForEach(VADMode.allCases) { mode in
                                                Text(mode.displayName).tag(mode)
                                            }
                                        }
                                        .pickerStyle(.segmented)
                                    }
                                }

                                if viewModel.vadMode == .off {
                                    GridRow {
                                        LabeledContent("Commit Interval") {
                                            Picker("Commit Interval", selection: $viewModel.manualCommitInterval) {
                                                ForEach(ManualCommitInterval.options) { option in
                                                    Text(option.label).tag(option)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            if viewModel.vadMode == .server {
                                DisclosureGroup(
                                    isExpanded: $serverVADExpanded,
                                    content: {
                                        LazyVGrid(columns: tuningColumns, alignment: .leading, spacing: 12) {
                                            OptionalDoubleField(
                                                title: "Threshold",
                                                value: $viewModel.serverVAD.threshold,
                                            )
                                            OptionalIntField(
                                                title: "Prefix Padding (ms)",
                                                value: $viewModel.serverVAD.prefixPaddingMs,
                                            )
                                            OptionalIntField(
                                                title: "Silence Duration (ms)",
                                                value: $viewModel.serverVAD.silenceDurationMs,
                                            )
                                            OptionalIntField(
                                                title: "Idle Timeout (ms)",
                                                value: $viewModel.serverVAD.idleTimeoutMs,
                                            )
                                        }
                                        .padding(.top, 8)
                                    },
                                    label: {
                                        HStack {
                                            Text("Server VAD Tuning")
                                            Spacer()
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            withAnimation(.snappy(duration: 0.2)) {
                                                serverVADExpanded.toggle()
                                            }
                                        }
                                    },
                                )
                                .padding(.top, 12)
                                .animation(.snappy(duration: 0.2), value: serverVADExpanded)
                            }
                        }
                    }
                    .padding(16)
                }
                .frame(minWidth: 340, maxWidth: 380, maxHeight: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

                GroupBox("Transcription Prompt") {
                    TextEditor(text: $viewModel.transcriptionPrompt)
                        .font(.callout)
                        .frame(maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(minWidth: 960, minHeight: 680)
    }

    private func statusColor(for status: RecordingStatus) -> Color {
        if case .error = status {
            return .red
        }
        if case .awaitingNetwork = status {
            return .orange
        }
        return .secondary
    }

    private func sectionCard(
        _ title: String,
        @ViewBuilder content: () -> some View,
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct OptionalDoubleField: View {
    let title: String
    @Binding var value: Double?
    @State private var text: String

    init(title: String, value: Binding<Double?>) {
        self.title = title
        _value = value
        _text = State(initialValue: value.wrappedValue.map { String($0) } ?? "")
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
        _value = value
        _text = State(initialValue: value.wrappedValue.map { String($0) } ?? "")
    }

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.roundedBorder)
            .onChange(of: text) { _, newValue in
                value = Int(newValue)
            }
    }
}
