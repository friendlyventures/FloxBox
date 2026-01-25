import Foundation

@MainActor
public protocol ShortcutBackend: AnyObject {
    var onTrigger: ((ShortcutTrigger) -> Void)? { get set }

    func start()
    func stop()
    func register(_ shortcuts: [ShortcutDefinition])
    func beginCapture(for id: ShortcutID, completion: @escaping (ShortcutDefinition?) -> Void)
}
