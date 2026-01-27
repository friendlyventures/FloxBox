import ApplicationServices

public struct InputMonitoringPermissionClient {
    public var isGranted: () -> Bool
    public var requestAccess: () -> Bool

    public init(
        isGranted: @escaping () -> Bool = { CGPreflightListenEventAccess() },
        requestAccess: @escaping () -> Bool = { CGRequestListenEventAccess() },
    ) {
        self.isGranted = isGranted
        self.requestAccess = requestAccess
    }
}
