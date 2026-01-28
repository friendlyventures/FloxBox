@testable import FloxBoxCore
import XCTest

@MainActor
final class DictationInjectionControllerTests: XCTestCase {
    func testInsertFinalUsesAXWhenAvailable() {
        let inserter = TestTextInserter(success: true)
        let fallback = TestTextInserter(success: false)
        let injector = DictationInjectionController(
            inserter: inserter,
            fallbackInserter: fallback,
            frontmostAppProvider: { "com.apple.TextEdit" },
            bundleIdentifier: "com.floxbox.app",
        )

        injector.startSession()
        _ = injector.insertFinal(text: "hello")
        let result = injector.finishSession()

        XCTAssertEqual(inserter.insertedTexts, ["hello"])
        XCTAssertEqual(fallback.insertedTexts, [])
        XCTAssertFalse(result.requiresManualPaste)
    }

    func testInsertFinalFallsBackToCGEventWhenAXFails() {
        let ax = TestTextInserter(success: false)
        let cg = TestTextInserter(success: true)
        let injector = DictationInjectionController(
            inserter: ax,
            fallbackInserter: cg,
            frontmostAppProvider: { "com.apple.TextEdit" },
            bundleIdentifier: "com.floxbox.app",
        )

        injector.startSession()
        _ = injector.insertFinal(text: "hello")
        let result = injector.finishSession()

        XCTAssertEqual(ax.insertedTexts, ["hello"])
        XCTAssertEqual(cg.insertedTexts, ["hello"])
        XCTAssertFalse(result.requiresManualPaste)
    }

    func testInsertFinalAddsLeadingSpaceWhenPrecedingCharIsNonWhitespace() {
        let inserter = TestTextInserter(success: true)
        let provider = TestFocusedTextContextProvider(value: "foo", caretIndex: 3)
        let injector = DictationInjectionController(
            inserter: inserter,
            fallbackInserter: TestTextInserter(success: false),
            focusedTextContextProvider: provider,
            frontmostAppProvider: { "com.apple.TextEdit" },
            bundleIdentifier: "com.floxbox.app",
        )

        injector.startSession()
        _ = injector.insertFinal(text: "bar")

        XCTAssertEqual(inserter.insertedTexts, [" bar"])
    }

    func testFrontmostIsFloxBoxMarksFailure() {
        let inserter = TestTextInserter(success: true)
        let injector = DictationInjectionController(
            inserter: inserter,
            fallbackInserter: TestTextInserter(success: true),
            frontmostAppProvider: { "com.floxbox.app" },
            bundleIdentifier: "com.floxbox.app",
        )

        injector.startSession()
        let didInsert = injector.insertFinal(text: "hello")
        let result = injector.finishSession()

        XCTAssertFalse(didInsert)
        XCTAssertTrue(result.requiresManualPaste)
        XCTAssertEqual(inserter.insertedTexts, [])
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
