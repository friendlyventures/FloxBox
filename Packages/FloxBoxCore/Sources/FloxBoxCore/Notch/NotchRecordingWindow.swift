import AppKit

// Adapted from the window style used by Boring.Notch / Atoll (GPLv3).
final class NotchRecordingWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false,
        )

        appearance = NSAppearance(named: .darkAqua)
        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = true

        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]

        isReleasedWhenClosed = false
        level = .mainMenu + 3
        hasShadow = false
    }

    override var canBecomeKey: Bool { false }

    override var canBecomeMain: Bool { false }

    func setAllowsMouseEvents(_ allowsMouseEvents: Bool) {
        ignoresMouseEvents = !allowsMouseEvents
    }
}
