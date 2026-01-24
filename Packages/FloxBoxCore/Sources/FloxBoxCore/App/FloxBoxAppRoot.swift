import SwiftUI

public enum FloxBoxAppRoot {
    public static func makeScene(
        configuration: FloxBoxDistributionConfiguration
    ) -> some Scene {
        WindowGroup {
            ContentView(configuration: configuration)
        }
    }
}
