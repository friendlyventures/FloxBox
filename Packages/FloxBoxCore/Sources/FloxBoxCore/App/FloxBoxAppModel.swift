import Foundation
import Observation

@MainActor
public protocol Coordinating {
    func start()
    func stop()
}

extension ShortcutCoordinator: Coordinating {}

extension PermissionsCoordinator: Coordinating {
    public func stop() {}
}

@Observable
@MainActor
public final class FloxBoxAppModel {
    public let configuration: FloxBoxDistributionConfiguration
    public let permissionsPresenter: PermissionsPresenter
    public var viewModel: TranscriptionViewModel
    public let shortcutStore: ShortcutStore
    public var formattingSettings: FormattingSettingsStore
    public var glossaryStore: PersonalGlossaryStore
    public let permissionsViewModel: PermissionsViewModel
    public let shortcutCoordinator: ShortcutCoordinator?
    public let permissionsCoordinator: PermissionsCoordinator?

    private let coordinators: [Coordinating]
    private let permissionsWindow: PermissionsWindowController

    public init(
        configuration: FloxBoxDistributionConfiguration,
        permissionsPresenter: PermissionsPresenter? = nil,
        viewModel: TranscriptionViewModel? = nil,
        shortcutStore: ShortcutStore? = nil,
        formattingSettings: FormattingSettingsStore? = nil,
        glossaryStore: PersonalGlossaryStore? = nil,
        makePermissionsCoordinator: (() -> Coordinating)? = nil,
        makeShortcutCoordinator: (() -> Coordinating)? = nil,
    ) {
        let resolvedPresenter = permissionsPresenter ?? PermissionsPresenter()
        let resolvedShortcutStore = shortcutStore ?? ShortcutStore()
        let resolvedFormattingSettings = formattingSettings ?? FormattingSettingsStore()
        let resolvedGlossaryStore = glossaryStore ?? PersonalGlossaryStore()
        let resolvedViewModel = viewModel ?? TranscriptionViewModel(
            permissionsPresenter: {
                resolvedPresenter.present()
            },
            formattingSettings: resolvedFormattingSettings,
            glossaryStore: resolvedGlossaryStore,
        )

        let inputMonitoringClient = InputMonitoringPermissionClient()
        let accessibilityClient = AccessibilityPermissionClient()
        let microphoneClient = MicrophonePermissionClient()
        let settingsOpener = SystemSettingsOpener()
        let permissionsViewModel = PermissionsViewModel(
            inputMonitoringClient: inputMonitoringClient,
            accessibilityClient: accessibilityClient,
            microphoneClient: microphoneClient,
            settingsOpener: settingsOpener,
        )
        let permissionsWindow = PermissionsWindowController(viewModel: permissionsViewModel)

        let defaultPermissionsCoordinator = PermissionsCoordinator(
            permissionChecker: {
                await permissionsViewModel.refresh()
                return permissionsViewModel.allGranted
            },
            requestAccess: {
                await permissionsViewModel.requestAllAccess()
            },
            window: permissionsWindow,
        )
        permissionsWindow.onClose = { [weak defaultPermissionsCoordinator] in
            defaultPermissionsCoordinator?.suppressAutoPresentation()
        }

        let defaultShortcutCoordinator = ShortcutCoordinator(
            store: resolvedShortcutStore,
            actions: ShortcutActions(
                startRecording: { resolvedViewModel.start() },
                stopRecording: { Task { await resolvedViewModel.stopAndWait() } },
            ),
        )

        let permissionsCoordinator = makePermissionsCoordinator?() ?? defaultPermissionsCoordinator
        let shortcutCoordinator = makeShortcutCoordinator?() ?? defaultShortcutCoordinator

        self.configuration = configuration
        self.permissionsPresenter = resolvedPresenter
        self.viewModel = resolvedViewModel
        self.shortcutStore = resolvedShortcutStore
        self.formattingSettings = resolvedFormattingSettings
        self.glossaryStore = resolvedGlossaryStore
        self.permissionsViewModel = permissionsViewModel
        self.permissionsWindow = permissionsWindow
        self.permissionsCoordinator = permissionsCoordinator as? PermissionsCoordinator
        self.shortcutCoordinator = shortcutCoordinator as? ShortcutCoordinator
        coordinators = [permissionsCoordinator, shortcutCoordinator]

        if let permissionsCoordinator = self.permissionsCoordinator {
            resolvedPresenter.coordinator = permissionsCoordinator
        }
    }

    public func start() {
        viewModel.refreshInputDevices()
        configuration.onAppear?()
        coordinators.forEach { $0.start() }
    }

    public func stop() {
        coordinators.forEach { $0.stop() }
    }

    public func presentPermissions() {
        permissionsPresenter.present()
    }

    public static func preview(configuration: FloxBoxDistributionConfiguration) -> FloxBoxAppModel {
        FloxBoxAppModel(configuration: configuration)
    }
}
