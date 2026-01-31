@testable import FloxBoxCore
import XCTest

@MainActor
final class DictationInjectionControllerTests: XCTestCase {
    func testInsertFinalUsesClipboardInserter() {
        let clipboard = TestTextInserter(success: true)
        let provider = TestFocusedTextContextProvider(value: "", caretIndex: 0)
        let injector = DictationInjectionController(
            clipboardInserter: clipboard,
            focusedTextContextProvider: provider,
            frontmostAppProvider: { "com.apple.TextEdit" },
            bundleIdentifier: "com.floxbox.app",
        )

        injector.startSession()
        let didInsert = injector.insertFinal(text: "hello")
        let result = injector.finishSession()

        XCTAssertTrue(didInsert)
        XCTAssertEqual(clipboard.insertedTexts, ["hello"])
        XCTAssertFalse(result.requiresManualPaste)
    }

    func testInsertFinalMarksFailureWhenClipboardFails() {
        let clipboard = TestTextInserter(success: false)
        let provider = TestFocusedTextContextProvider(value: "", caretIndex: 0)
        let injector = DictationInjectionController(
            clipboardInserter: clipboard,
            focusedTextContextProvider: provider,
            frontmostAppProvider: { "com.apple.TextEdit" },
            bundleIdentifier: "com.floxbox.app",
        )

        injector.startSession()
        let didInsert = injector.insertFinal(text: "hello")
        let result = injector.finishSession()

        XCTAssertFalse(didInsert)
        XCTAssertEqual(clipboard.insertedTexts, ["hello"])
        XCTAssertTrue(result.requiresManualPaste)
    }

    func testInsertFinalAddsLeadingSpaceWhenPrecedingCharIsNonWhitespace() {
        let clipboard = TestTextInserter(success: true)
        let provider = TestFocusedTextContextProvider(value: "foo", caretIndex: 3)
        let injector = DictationInjectionController(
            clipboardInserter: clipboard,
            focusedTextContextProvider: provider,
            frontmostAppProvider: { "com.apple.TextEdit" },
            bundleIdentifier: "com.floxbox.app",
        )

        injector.startSession()
        _ = injector.insertFinal(text: "bar")

        XCTAssertEqual(clipboard.insertedTexts, [" bar"])
    }

    func testFrontmostIsFloxBoxMarksFailure() {
        let clipboard = TestTextInserter(success: true)
        let injector = DictationInjectionController(
            clipboardInserter: clipboard,
            frontmostAppProvider: { "com.floxbox.app" },
            bundleIdentifier: "com.floxbox.app",
        )

        injector.startSession()
        let didInsert = injector.insertFinal(text: "hello")
        let result = injector.finishSession()

        XCTAssertFalse(didInsert)
        XCTAssertTrue(result.requiresManualPaste)
        XCTAssertEqual(clipboard.insertedTexts, [])
    }
}

private struct TestFocusedTextContextProvider: FocusedTextContextProviding {
    let value: String
    let caretIndex: Int

    func focusedTextContext() -> FocusedTextContext? {
        FocusedTextContext(value: value, caretIndex: caretIndex)
    }
}

private final class TestTextInserter: DictationTextInserting {
    let success: Bool
    private(set) var insertedTexts: [String] = []

    init(success: Bool) {
        self.success = success
    }

    func insert(text: String) -> Bool {
        insertedTexts.append(text)
        return success
    }
}
