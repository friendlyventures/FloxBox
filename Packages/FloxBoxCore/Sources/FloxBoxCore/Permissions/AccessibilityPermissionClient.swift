import ApplicationServices

public struct AccessibilityPermissionClient {
    public var isTrusted: () -> Bool
    public var requestAccess: () -> Void

    public init(
        isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        requestAccess: @escaping () -> Void = {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        },
    ) {
        self.isTrusted = isTrusted
        self.requestAccess = requestAccess
    }
}
