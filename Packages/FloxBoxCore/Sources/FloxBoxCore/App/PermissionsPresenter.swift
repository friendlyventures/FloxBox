import Foundation

@MainActor
public final class PermissionsPresenter {
    public var coordinator: PermissionsCoordinator?

    public init() {}

    public func present() {
        coordinator?.bringToFront()
    }
}
