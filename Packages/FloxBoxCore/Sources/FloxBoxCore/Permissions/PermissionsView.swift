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
        VStack(alignment: .leading, spacing: 16) {
            permissionRow(
                title: "Input Monitoring",
                description: "Needed for push-to-talk hotkey detection.",
                granted: viewModel.inputMonitoringGranted,
                action: { Task { await viewModel.requestInputMonitoringAccess() } },
            )

            Divider()

            permissionRow(
                title: "Accessibility",
                description: "Needed to type into other apps.",
                granted: viewModel.accessibilityGranted,
                action: { Task { await viewModel.requestAccessibilityAccess() } },
            )

            Divider()

            permissionRow(
                title: "Microphone",
                description: "Needed to capture dictation audio.",
                granted: viewModel.microphoneGranted,
                action: { Task { await viewModel.requestMicrophoneAccess() } },
            )

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 360)
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        description: String,
        granted: Bool,
        action: @escaping () -> Void,
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Request Access", action: action)
                Text(granted ? "Granted" : "Not Granted")
                    .foregroundStyle(granted ? .green : .red)
            }
        }
    }
}
