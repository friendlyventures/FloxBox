import Foundation
import UserNotifications

@MainActor
public final class SystemNotificationPresenter: NSObject, ToastPresenting {
    private enum Constants {
        static let actionIdentifier = "FloxBoxToastAction"
        static let categoryIdentifier = "FloxBoxToastCategory"
        static let toastDelayNanos: UInt64 = 150_000_000
    }

    private let center: UNUserNotificationCenter?
    private var pendingMessage: String?
    private var pendingToastTask: Task<Void, Never>?
    private var actionHandlers: [String: () -> Void] = [:]

    public init(center: UNUserNotificationCenter? = nil) {
        let resolvedCenter = center ?? Self.defaultCenter()
        self.center = resolvedCenter
        super.init()
        resolvedCenter?.delegate = self
    }

    public func showToast(_ message: String) {
        pendingMessage = message
        schedulePendingToast()
    }

    public func showAction(title: String, handler: @escaping () -> Void) {
        let message = pendingMessage ?? "FloxBox"
        pendingToastTask?.cancel()
        pendingToastTask = nil
        pendingMessage = nil
        scheduleNotification(message: message, actionTitle: title, handler: handler)
    }

    public func clearToast() {
        pendingToastTask?.cancel()
        pendingToastTask = nil
        pendingMessage = nil
    }

    private func schedulePendingToast() {
        pendingToastTask?.cancel()
        pendingToastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Constants.toastDelayNanos)
            guard let self, let message = pendingMessage else { return }
            pendingMessage = nil
            scheduleNotification(message: message, actionTitle: nil, handler: nil)
        }
    }

    private func scheduleNotification(
        message: String,
        actionTitle: String?,
        handler: (() -> Void)?,
    ) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "FloxBox"
        content.body = message

        if let actionTitle {
            let action = UNNotificationAction(
                identifier: Constants.actionIdentifier,
                title: actionTitle,
                options: [.foreground],
            )
            let category = UNNotificationCategory(
                identifier: Constants.categoryIdentifier,
                actions: [action],
                intentIdentifiers: [],
                options: [],
            )
            center.setNotificationCategories([category])
            content.categoryIdentifier = Constants.categoryIdentifier
        }

        let requestID = UUID().uuidString
        if let handler {
            actionHandlers[requestID] = handler
        }

        let request = UNNotificationRequest(identifier: requestID, content: content, trigger: nil)
        center.add(request)
    }

    private static func defaultCenter() -> UNUserNotificationCenter? {
        guard !isRunningTests() else { return nil }
        return UNUserNotificationCenter.current()
    }

    private static func isRunningTests() -> Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil {
            return true
        }
        if NSClassFromString("XCTestCase") != nil {
            return true
        }
        return false
    }
}

extension SystemNotificationPresenter: UNUserNotificationCenterDelegate {
    public nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void,
    ) {
        Task { @MainActor in
            completionHandler([.banner])
        }
    }

    public nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void,
    ) {
        Task { @MainActor in
            defer { completionHandler() }
            guard response.actionIdentifier == Constants.actionIdentifier else { return }
            let requestID = response.notification.request.identifier
            let handler = actionHandlers.removeValue(forKey: requestID)
            handler?()
        }
    }
}
