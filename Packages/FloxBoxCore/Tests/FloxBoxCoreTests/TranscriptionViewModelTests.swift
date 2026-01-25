import XCTest
@testable import FloxBoxCore

@MainActor
final class TranscriptionViewModelTests: XCTestCase {
    func testDefaults() {
        let viewModel = TranscriptionViewModel(keychain: InMemoryKeychainStore())
        XCTAssertEqual(viewModel.model, .defaultModel)
        XCTAssertEqual(viewModel.language, .defaultLanguage)
        XCTAssertEqual(viewModel.noiseReduction, .defaultOption)
        XCTAssertNil(viewModel.selectedInputDeviceID)
        XCTAssertEqual(viewModel.vadMode, .server)
        XCTAssertEqual(viewModel.manualCommitInterval, .defaultInterval)
        XCTAssertEqual(viewModel.status, .idle)
        XCTAssertEqual(viewModel.transcript, "")
        XCTAssertEqual(viewModel.apiKeyInput, "")
        XCTAssertEqual(viewModel.apiKeyStatus, .idle)
    }

    func testLoadsAPIKeyFromKeychain() {
        let keychain = InMemoryKeychainStore()
        try? keychain.save("sk-test")
        let viewModel = TranscriptionViewModel(keychain: keychain)

        XCTAssertEqual(viewModel.apiKeyInput, "sk-test")
    }

    func testSaveClearsKeychainWhenEmpty() {
        let keychain = InMemoryKeychainStore()
        let viewModel = TranscriptionViewModel(keychain: keychain)

        viewModel.apiKeyInput = ""
        viewModel.saveAPIKey()

        XCTAssertNil(try? keychain.load())
        XCTAssertEqual(viewModel.apiKeyStatus, .cleared)
    }
}
