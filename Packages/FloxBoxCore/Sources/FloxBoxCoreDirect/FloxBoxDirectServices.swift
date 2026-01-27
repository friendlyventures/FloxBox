import FloxBoxCore
import SwiftUI

@MainActor
public enum FloxBoxDirectServices {
    private static let updaterController = UpdaterController()

    public static func configuration() -> FloxBoxDistributionConfiguration {
        FloxBoxDistributionConfiguration(
            label: FloxBoxDistributionConfiguration.direct.label,
            updatesView: AnyView(UpdatesView(updaterController: updaterController)),
            checkForUpdates: {
                updaterController.checkForUpdates()
            },
            onAppear: {
                Task { @MainActor in
                    updaterController.checkForUpdatesOnLaunchIfNeeded()
                }
            },
        )
    }
}
