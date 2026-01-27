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
    private var spinnerTask: Task<Void, Never>?

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

    func showRecording() {
        hideTask?.cancel()
        hideTask = nil
        spinnerTask?.cancel()
        spinnerTask = nil

        ensureWindow()
        window?.orderFrontRegardless()
        window?.setAllowsMouseEvents(false)
        state.isAwaitingNetwork = false
        state.showNetworkSpinner = false
        state.onCancel = nil
        state.isRecording = true
        withAnimation(.interpolatingSpring(stiffness: 260, damping: 18)) {
            state.isExpanded = true
        }
    }

    func showAwaitingNetwork(onCancel: @escaping () -> Void) {
        hideTask?.cancel()
        hideTask = nil
        spinnerTask?.cancel()
        spinnerTask = nil

        ensureWindow()
        window?.orderFrontRegardless()
        window?.setAllowsMouseEvents(true)
        state.isRecording = false
        state.isAwaitingNetwork = true
        state.showNetworkSpinner = false
        state.onCancel = onCancel
        withAnimation(.interpolatingSpring(stiffness: 260, damping: 18)) {
            state.isExpanded = true
        }

        spinnerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                guard let self, self.state.isAwaitingNetwork else { return }
                self.state.showNetworkSpinner = true
            }
        }
    }

    func hide() {
        hideTask?.cancel()
        spinnerTask?.cancel()
        spinnerTask = nil
        state.isRecording = false
        state.isAwaitingNetwork = false
        state.showNetworkSpinner = false
        state.onCancel = nil
        withAnimation(.easeInOut(duration: 0.18)) {
            state.isExpanded = false
        }

        guard let window else { return }
        window.setAllowsMouseEvents(false)
        hideTask = Task { [weak window] in
            try? await Task.sleep(nanoseconds: Constants.closeDelayNanos)
            window?.orderOut(nil)
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
    }

    private func refreshLayoutIfVisible() {
        guard let window, window.isVisible else { return }
        ensureWindow()
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
