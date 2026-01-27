import SwiftUI

public enum FloxBoxAppRoot {
    @SceneBuilder
    public static func makeScene(
        model: FloxBoxAppModel,
    ) -> some Scene {
        MenuBarExtra("FloxBox", systemImage: "waveform") {
            MenubarMenu(model: model)
        }
        .menuBarExtraStyle(.menu)

        Window("Debug Panel", id: "debug") {
            DebugPanelView(model: model)
        }

        Window("Settings", id: "settings") {
            SettingsView(model: model)
        }
    }
}
