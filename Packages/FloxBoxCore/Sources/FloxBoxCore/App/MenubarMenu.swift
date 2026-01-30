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
        Button {
            model.viewModel.pasteLastTranscript()
        } label: {
            Label("Paste last transcript", systemImage: "clipboard")
        }
        .disabled(!hasLastTranscript)

        Divider()

        Button {
            openWindow(id: "settings")
        } label: {
            Label("Settings", systemImage: "gearshape")
        }

        if !permissionsViewModel.allGranted {
            Button {
                model.presentPermissions()
            } label: {
                Label("Permissions", systemImage: "hand.raised")
            }
        }

        if let checkForUpdates = model.configuration.checkForUpdates {
            Button {
                checkForUpdates()
            } label: {
                Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
            }
        }

        Button {
            openWindow(id: "debug")
        } label: {
            Label("Open Debug Panel", systemImage: "ladybug")
        }

        Divider()

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit FloxBox", systemImage: "power")
        }
    }

    var hasCheckForUpdatesAction: Bool {
        model.configuration.checkForUpdates != nil
    }

    var hasLastTranscript: Bool {
        let text = model.viewModel.lastFinalTranscript?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false
    }
}
