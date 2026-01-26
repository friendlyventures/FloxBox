import CoreAudio
import Observation
import SwiftUI

public struct ContentView: View {
    private let configuration: FloxBoxDistributionConfiguration
    @State private var viewModel = TranscriptionViewModel()
    @State private var shortcutStore = ShortcutStore()
    @State private var shortcutCoordinator: ShortcutCoordinator?
    @State private var updatesExpanded = false
    @State private var serverVADExpanded = false
    private let tuningColumns = [GridItem(.adaptive(minimum: 200), spacing: 12)]

    public init(configuration: FloxBoxDistributionConfiguration) {
        self.configuration = configuration
    }

    public var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FloxBox")
                        .font(.title2.weight(.semibold))
                    Text(configuration.label)
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
                            if let shortcutCoordinator {
                                ShortcutRecorderView(
                                    store: shortcutStore,
                                    coordinator: shortcutCoordinator,
                                )
                            }
                        }

                        if let updatesView = configuration.updatesView {
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

                GeometryReader { proxy in
                    let spacing: CGFloat = 16
                    let availableHeight = max(0, proxy.size.height - spacing)
                    let transcriptHeight = availableHeight * 0.67
                    let promptHeight = availableHeight * 0.33

                    VStack(alignment: .leading, spacing: spacing) {
                        GroupBox("Transcript") {
                            TextEditor(text: $viewModel.transcript)
                                .font(.body)
                                .frame(maxHeight: .infinity)
                        }
                        .frame(height: transcriptHeight)

                        GroupBox("Transcription Prompt") {
                            TextEditor(text: $viewModel.transcriptionPrompt)
                                .font(.callout)
                                .frame(maxHeight: .infinity)
                        }
                        .frame(height: promptHeight)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(minWidth: 960, minHeight: 680)
        .onAppear {
            viewModel.refreshInputDevices()
            configuration.onAppear?()

            if shortcutCoordinator == nil {
                shortcutCoordinator = ShortcutCoordinator(
                    store: shortcutStore,
                    actions: ShortcutActions(
                        startRecording: { viewModel.start() },
                        stopRecording: { Task { await viewModel.stopAndWait() } },
                    ),
                )
            }
            shortcutCoordinator?.start()
        }
        .onDisappear {
            shortcutCoordinator?.stop()
        }
    }

    private func statusColor(for status: RecordingStatus) -> Color {
        if case .error = status {
            return .red
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
