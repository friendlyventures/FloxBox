@testable import FloxBoxCore
import SwiftUI
import XCTest

@MainActor
final class ContentViewTests: XCTestCase {
    func testContentViewBuildsWithAPIKeyRow() {
        _ = ContentView(configuration: .appStore)
        _ = APIKeyRow(apiKey: .constant(""), status: .constant(.idle))
    }

    func testContentViewBuildsWithShortcutRecorder() {
        let store = ShortcutStore(userDefaults: UserDefaults(suiteName: "ShortcutRecorderTests")!)
        let coordinator = ShortcutCoordinator(
            store: store,
            backend: AppStoreShortcutBackend(),
            actions: ShortcutActions(startRecording: {}, stopRecording: {}),
        )
        _ = ShortcutRecorderView(store: store, coordinator: coordinator)
    }
}
