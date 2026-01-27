import AppKit
import SwiftUI

@MainActor
public protocol PermissionsWindowPresenting {
    func show()
    func hide()
    func bringToFront()
}

@MainActor
public final class PermissionsWindowController: NSObject, PermissionsWindowPresenting, NSWindowDelegate {
    private var window: NSWindow?
    private let viewModel: PermissionsViewModel
    public var onClose: (() -> Void)?

    public init(viewModel: PermissionsViewModel) {
        self.viewModel = viewModel
    }

    public func show() {
        ensureWindow()
        window?.orderFrontRegardless()
    }

    public func hide() {
        window?.orderOut(nil)
    }

    public func bringToFront() {
        ensureWindow()
        NSApp.activate(ignoringOtherApps: true)
        window?.orderFrontRegardless()
    }

    private func ensureWindow() {
        guard window == nil else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.title = "Permissions Required"
        window.contentView = NSHostingView(rootView: PermissionsView(viewModel: viewModel))
        self.window = window
    }

    @objc public func windowWillClose(_: Notification) {
        onClose?()
    }
}
