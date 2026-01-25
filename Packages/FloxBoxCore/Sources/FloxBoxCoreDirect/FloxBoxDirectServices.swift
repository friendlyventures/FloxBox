import FloxBoxCore
import SwiftUI

public enum FloxBoxDirectServices {
    private static let updaterController = UpdaterController()

    public static func configuration() -> FloxBoxDistributionConfiguration {
        FloxBoxDistributionConfiguration(
            label: FloxBoxDistributionConfiguration.direct.label,
            updatesView: AnyView(UpdatesView(updaterController: updaterController)),
            onAppear: {
                updaterController.checkForUpdatesOnLaunchIfNeeded()
            },
        )
    }
}
