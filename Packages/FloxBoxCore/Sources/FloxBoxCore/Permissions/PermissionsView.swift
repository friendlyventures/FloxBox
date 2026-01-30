import SwiftUI

@MainActor
public final class PermissionsViewModel: ObservableObject {
    @Published public var inputMonitoringGranted: Bool
    @Published public var accessibilityGranted: Bool
    @Published public var microphoneGranted: Bool
    private let inputMonitoringClient: InputMonitoringPermissionClient
    private let accessibilityClient: AccessibilityPermissionClient
    private let microphoneClient: MicrophonePermissionClient
    private let settingsOpener: SystemSettingsOpener

    public init(
        inputMonitoringClient: InputMonitoringPermissionClient,
        accessibilityClient: AccessibilityPermissionClient,
        microphoneClient: MicrophonePermissionClient,
        settingsOpener: SystemSettingsOpener,
    ) {
        self.inputMonitoringClient = inputMonitoringClient
        self.accessibilityClient = accessibilityClient
        self.microphoneClient = microphoneClient
        self.settingsOpener = settingsOpener
        inputMonitoringGranted = inputMonitoringClient.isGranted()
        accessibilityGranted = accessibilityClient.isTrusted()
        microphoneGranted = microphoneClient.authorizationStatus() == .authorized
    }

    public convenience init(
        permissionClient: AccessibilityPermissionClient,
        notificationClient: NotificationPermissionClient,
    ) {
        self.init(
            inputMonitoringClient: InputMonitoringPermissionClient(),
            accessibilityClient: permissionClient,
            microphoneClient: MicrophonePermissionClient(),
            settingsOpener: SystemSettingsOpener(),
        )
        _ = notificationClient
    }

    public var isTrusted: Bool {
        accessibilityGranted
    }

    public var notificationsGranted: Bool {
        microphoneGranted
    }

    public var allGranted: Bool {
        inputMonitoringGranted && accessibilityGranted && microphoneGranted
    }

    public func refresh() async {
        inputMonitoringGranted = inputMonitoringClient.isGranted()
        accessibilityGranted = accessibilityClient.isTrusted()
        microphoneGranted = microphoneClient.authorizationStatus() == .authorized
    }

    public func requestInputMonitoringAccess() async {
        _ = inputMonitoringClient.requestAccess()
        settingsOpener.open()
        await refresh()
    }

    public func requestAccessibilityAccess() async {
        accessibilityClient.requestAccess()
        settingsOpener.open()
        await refresh()
    }

    public func requestNotificationAccess() async {
        await requestMicrophoneAccess()
    }

    public func requestMicrophoneAccess() async {
        _ = await microphoneClient.requestAccess()
        settingsOpener.open()
        await refresh()
    }

    public func requestAllAccess() async {
        _ = inputMonitoringClient.requestAccess()
        accessibilityClient.requestAccess()
        _ = await microphoneClient.requestAccess()
        settingsOpener.open()
        await refresh()
    }
}

public struct PermissionsView: View {
    @ObservedObject var viewModel: PermissionsViewModel

    public init(viewModel: PermissionsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            if !viewModel.allGranted {
                Button {
                    Task { await viewModel.requestAllAccess() }
                } label: {
                    Label("Request All Permissions", systemImage: "checkmark.seal")
                }
                .buttonStyle(.borderedProminent)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("All permissions granted.")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }

            permissionCard(
                PermissionCard(
                    title: "Input Monitoring",
                    description: "Needed for push-to-talk hotkey detection.",
                    systemImage: "keyboard",
                    granted: viewModel.inputMonitoringGranted,
                    actionTitle: "Request Input Monitoring",
                    action: { Task { await viewModel.requestInputMonitoringAccess() } },
                ),
            )

            permissionCard(
                PermissionCard(
                    title: "Accessibility",
                    description: "Needed to type into other apps.",
                    systemImage: "hand.raised",
                    granted: viewModel.accessibilityGranted,
                    actionTitle: "Request Accessibility",
                    action: { Task { await viewModel.requestAccessibilityAccess() } },
                ),
            )

            permissionCard(
                PermissionCard(
                    title: "Microphone",
                    description: "Needed to capture dictation audio.",
                    systemImage: "mic",
                    granted: viewModel.microphoneGranted,
                    actionTitle: "Request Microphone",
                    action: { Task { await viewModel.requestMicrophoneAccess() } },
                ),
            )

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 420)
        .task { await viewModel.refresh() }
    }

    private struct PermissionCard {
        let title: String
        let description: String
        let systemImage: String
        let granted: Bool
        let actionTitle: String
        let action: () -> Void
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "hand.raised.square.fill")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Permissions")
                    .font(.title2.weight(.semibold))
                Text("FloxBox needs a few macOS permissions to listen and type for you.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func permissionCard(_ card: PermissionCard) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(card.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    statusBadge(granted: card.granted)
                    Spacer()
                    Button(card.actionTitle, action: card.action)
                        .buttonStyle(.bordered)
                }
            }
            .padding(.top, 4)
        } label: {
            Label(card.title, systemImage: card.systemImage)
                .font(.headline)
        }
    }

    private func statusBadge(granted: Bool) -> some View {
        Text(granted ? "Granted" : "Not Granted")
            .font(.caption.weight(.semibold))
            .foregroundStyle(granted ? .green : .red)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(granted ? Color.green.opacity(0.15) : Color.red.opacity(0.12))
            .clipShape(Capsule())
    }
}
