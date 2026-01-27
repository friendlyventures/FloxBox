import AppKit
import SwiftUI

public struct MenubarMenu: View {
    public let model: FloxBoxAppModel
    @ObservedObject private var permissionsViewModel: PermissionsViewModel
    @Environment(\.openWindow) private var openWindow

    public init(model: FloxBoxAppModel) {
        self.model = model
        _permissionsViewModel = ObservedObject(wrappedValue: model.permissionsViewModel)
    }

    public var body: some View {
        Button("Open Debug Panel") {
            openWindow(id: "debug")
        }

        Button("Settings") {
            openWindow(id: "settings")
        }

        if !permissionsViewModel.isTrusted {
            Divider()
            Button("Permissions") {
                model.presentPermissions()
            }
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}
