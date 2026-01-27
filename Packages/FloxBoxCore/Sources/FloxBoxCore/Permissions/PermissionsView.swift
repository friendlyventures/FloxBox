import SwiftUI
import UserNotifications

@MainActor
public final class PermissionsViewModel: ObservableObject {
    @Published public var isTrusted: Bool
    @Published public var notificationStatus: UNAuthorizationStatus
    private let permissionClient: AccessibilityPermissionClient
    private let notificationClient: NotificationPermissionClient

    public init(
        permissionClient: AccessibilityPermissionClient,
        notificationClient: NotificationPermissionClient,
    ) {
        self.permissionClient = permissionClient
        self.notificationClient = notificationClient
        isTrusted = permissionClient.isTrusted()
        notificationStatus = .notDetermined
    }

    public var notificationsGranted: Bool {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            true
        case .denied, .notDetermined:
            false
        @unknown default:
            false
        }
    }

    public var allGranted: Bool {
        isTrusted && notificationsGranted
    }

    public func refresh() async {
        isTrusted = permissionClient.isTrusted()
        notificationStatus = await notificationClient.fetchStatus()
    }

    public func requestAccessibilityAccess() async {
        permissionClient.requestAccess()
        await refresh()
    }

    public func requestNotificationAccess() async {
        _ = await notificationClient.requestAuthorization()
        await refresh()
    }

    public func requestAllAccess() async {
        permissionClient.requestAccess()
        _ = await notificationClient.requestAuthorization()
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
            VStack(alignment: .leading, spacing: 12) {
                Text("Allow Accessibility")
                    .font(.headline)
                Text("FloxBox needs Accessibility access to type into other apps.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Request Access") {
                        Task { await viewModel.requestAccessibilityAccess() }
                    }
                    if viewModel.isTrusted {
                        Text("Granted").foregroundStyle(.green)
                    } else {
                        Text("Missing").foregroundStyle(.red)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Enable Notifications")
                    .font(.headline)
                Text("FloxBox uses notifications for status and error messages.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Request Access") {
                        Task { await viewModel.requestNotificationAccess() }
                    }
                    if viewModel.notificationsGranted {
                        Text("Granted").foregroundStyle(.green)
                    } else {
                        Text("Missing").foregroundStyle(.red)
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 300)
    }
}
