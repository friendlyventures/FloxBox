import Foundation

@MainActor
public protocol ToastPresenting: AnyObject {
    func showToast(_ message: String)
    func showAction(title: String, handler: @escaping () -> Void)
    func clearToast()
}

@MainActor
final class NoopToastPresenter: ToastPresenting {
    func showToast(_: String) {}
    func showAction(title _: String, handler _: @escaping () -> Void) {}
    func clearToast() {}
}
