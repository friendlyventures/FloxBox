import AppKit

// Sized to match the notch sizing logic used in Boring.Notch / Atoll (GPLv3).
struct NotchMetrics: Equatable {
    let hasNotch: Bool
    let closedSize: CGSize
    let menuBarHeight: CGFloat
    let screenFrame: CGRect
}

enum NotchSizing {
    static func metrics(for screen: NSScreen) -> NotchMetrics {
        let screenFrame = screen.frame
        let menuBarHeight = screenFrame.maxY - screen.visibleFrame.maxY
        let hasNotch = screen.safeAreaInsets.top > 0
        let notchHeight = hasNotch ? screen.safeAreaInsets.top : menuBarHeight
        let notchWidth: CGFloat = if let left = screen.auxiliaryTopLeftArea?.width,
                                     let right = screen.auxiliaryTopRightArea?.width
        {
            screenFrame.width - left - right + 4
        } else {
            185
        }

        return NotchMetrics(
            hasNotch: hasNotch,
            closedSize: CGSize(width: notchWidth, height: notchHeight),
            menuBarHeight: menuBarHeight,
            screenFrame: screenFrame,
        )
    }
}
