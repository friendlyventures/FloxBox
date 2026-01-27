import AppKit

public struct SystemSettingsOpener {
    public var open: () -> Void

    public init(open: @escaping () -> Void = {
        let url = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        NSWorkspace.shared.open(url)
    }) {
        self.open = open
    }
}
