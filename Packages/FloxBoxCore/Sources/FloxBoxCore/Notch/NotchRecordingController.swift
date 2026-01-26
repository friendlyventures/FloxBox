import AppKit
import SwiftUI

@MainActor
final class NotchRecordingController {
    private enum Constants {
        static let openExpansion: CGFloat = 64
        static let containerPadding: CGFloat = 32
        static let minimumHeight: CGFloat = 24
        static let closeDelayNanos: UInt64 = 260_000_000
    }

    private let state = NotchRecordingState()
    private var window: NotchRecordingWindow?
    private var screenObserver: NSObjectProtocol?
    private var hideTask: Task<Void, Never>?

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshLayoutIfVisible()
            }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func show() {
        hideTask?.cancel()
        hideTask = nil

        ensureWindow()
        window?.orderFrontRegardless()
        state.toastMessage = nil
        state.action = nil
        state.isRecording = true
        withAnimation(.interpolatingSpring(stiffness: 260, damping: 18)) {
            state.isExpanded = true
        }
        updateMouseHandling()
    }

    func hide() {
        hideTask?.cancel()
        state.isRecording = false
        withAnimation(.easeInOut(duration: 0.18)) {
            state.isExpanded = false
        }
        updateMouseHandling()

        guard let window else { return }
        hideTask = Task { [weak window] in
            try? await Task.sleep(nanoseconds: Constants.closeDelayNanos)
            window?.orderOut(nil)
        }
    }

    func showToast(_ message: String) {
        hideTask?.cancel()
        hideTask = nil
        ensureWindow()
        window?.orderFrontRegardless()
        state.isRecording = false
        state.toastMessage = message
        state.action = nil
        withAnimation(.interpolatingSpring(stiffness: 260, damping: 18)) {
            state.isExpanded = true
        }
        updateMouseHandling()
    }

    func showAction(title: String, handler: @escaping () -> Void) {
        hideTask?.cancel()
        hideTask = nil
        ensureWindow()
        window?.orderFrontRegardless()
        state.isRecording = false
        state.action = NotchRecordingAction(title: title, handler: handler)
        withAnimation(.interpolatingSpring(stiffness: 260, damping: 18)) {
            state.isExpanded = true
        }
        updateMouseHandling()
    }

    func clearToast() {
        state.toastMessage = nil
        state.action = nil
        updateMouseHandling()
        if !state.isRecording {
            hide()
        }
    }

    private func ensureWindow() {
        guard let screen = preferredScreen() else { return }
        let layout = layout(for: screen)
        state.layout = layout

        let frame = frame(for: layout, on: screen)

        if let window {
            window.setFrame(frame, display: true)
            window.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        } else {
            let window = NotchRecordingWindow(contentRect: frame)
            let rootView = NotchRecordingView(state: state)
            let hostingView = NSHostingView(rootView: rootView)
            hostingView.frame = NSRect(origin: .zero, size: frame.size)
            window.contentView = hostingView
            window.orderOut(nil)
            self.window = window
        }
        updateMouseHandling()
    }

    private func refreshLayoutIfVisible() {
        guard let window, window.isVisible else { return }
        ensureWindow()
    }

    private func updateMouseHandling() {
        window?.ignoresMouseEvents = state.action == nil
    }

    private func preferredScreen() -> NSScreen? {
        if let screen = NSApp.keyWindow?.screen {
            return screen
        }
        if let screen = NSApp.mainWindow?.screen {
            return screen
        }
        return NSScreen.main
    }

    private func layout(for screen: NSScreen) -> NotchRecordingLayout {
        let metrics = NotchSizing.metrics(for: screen)
        let height = max(metrics.closedSize.height, Constants.minimumHeight)
        let closedWidth = metrics.closedSize.width
        let openWidth = closedWidth + Constants.openExpansion
        let containerWidth = openWidth + (Constants.containerPadding * 2)
        return NotchRecordingLayout(
            closedWidth: closedWidth,
            openWidth: openWidth,
            containerWidth: containerWidth,
            height: height,
        )
    }

    private func frame(for layout: NotchRecordingLayout, on screen: NSScreen) -> NSRect {
        let metrics = NotchSizing.metrics(for: screen)
        let screenFrame = metrics.screenFrame
        let height = layout.height
        let width = layout.containerWidth
        let originY = screenFrame.maxY - height
        let originX = screenFrame.midX - (width / 2)

        return NSRect(x: originX, y: originY, width: width, height: height)
    }
}
