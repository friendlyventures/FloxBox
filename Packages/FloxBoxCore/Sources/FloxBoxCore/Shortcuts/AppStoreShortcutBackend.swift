import Foundation

@MainActor
public final class AppStoreShortcutBackend: ShortcutBackend {
    public var onTrigger: ((ShortcutTrigger) -> Void)?

    public init() {}

    public func start() {}

    public func stop() {}

    public func register(_: [ShortcutDefinition]) {}

    public func beginCapture(for _: ShortcutID, completion: @escaping (ShortcutDefinition?) -> Void) {
        completion(nil)
    }
}
