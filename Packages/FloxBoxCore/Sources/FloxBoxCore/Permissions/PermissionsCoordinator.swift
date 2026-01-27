import Foundation

@MainActor
public final class PermissionsCoordinator {
    private let permissionChecker: () async -> Bool
    private let requestAccess: () async -> Void
    private let window: PermissionsWindowPresenting
    private var timer: Timer?
    private var allowAutoPresentation = true

    public init(
        permissionChecker: @escaping () async -> Bool,
        requestAccess: @escaping () async -> Void,
        window: PermissionsWindowPresenting,
    ) {
        self.permissionChecker = permissionChecker
        self.requestAccess = requestAccess
        self.window = window
    }

    public func start() {
        allowAutoPresentation = true
        Task { await refresh() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    public func refresh() async {
        if await permissionChecker() {
            window.hide()
        } else if allowAutoPresentation {
            window.show()
        }
    }

    public func bringToFront() {
        allowAutoPresentation = true
        window.bringToFront()
    }

    public func suppressAutoPresentation() {
        allowAutoPresentation = false
    }

    public func request() {
        allowAutoPresentation = true
        Task {
            await requestAccess()
            await refresh()
        }
    }
}
