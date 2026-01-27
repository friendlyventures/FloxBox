@testable import FloxBoxCore
import XCTest

@MainActor
final class DictationInjectionControllerTests: XCTestCase {
    func testApplyTextPostsBackspacesAndInsert() {
        let poster = TestEventPoster()
        let coalescer = ImmediateCoalescer()
        let injector = DictationInjectionController(
            eventPoster: poster,
            coalescer: coalescer,
            frontmostAppProvider: { "com.apple.TextEdit" },
            bundleIdentifier: "com.floxbox.app",
        )

        injector.startSession()
        injector.apply(text: "hello")
        injector.apply(text: "hel")

        XCTAssertEqual(poster.backspaceCount, 2)
        XCTAssertEqual(poster.inserted, ["hello", ""])
    }

    func testAddsLeadingSpaceWhenPrecedingCharIsNonWhitespace() {
        let poster = TestEventPoster()
        let coalescer = ImmediateCoalescer()
        let provider = TestFocusedTextContextProvider(value: "foo bar", caretIndex: 7)
        let injector = DictationInjectionController(
            eventPoster: poster,
            coalescer: coalescer,
            focusedTextContextProvider: provider,
            frontmostAppProvider: { "com.apple.TextEdit" },
            bundleIdentifier: "com.floxbox.app",
        )

        injector.startSession()
        injector.apply(text: "baz")

        XCTAssertEqual(poster.inserted, [" baz"])
    }

    func testDoesNotAddLeadingSpaceWhenDictationStartsWithPunctuation() {
        let poster = TestEventPoster()
        let coalescer = ImmediateCoalescer()
        let provider = TestFocusedTextContextProvider(value: "foo", caretIndex: 3)
        let injector = DictationInjectionController(
            eventPoster: poster,
            coalescer: coalescer,
            focusedTextContextProvider: provider,
            frontmostAppProvider: { "com.apple.TextEdit" },
            bundleIdentifier: "com.floxbox.app",
        )

        injector.startSession()
        injector.apply(text: ",")

        XCTAssertEqual(poster.inserted, [","])
    }

    func testPrefixInsertedOnceAcrossUpdates() {
        let poster = TestEventPoster()
        let coalescer = ImmediateCoalescer()
        let provider = TestFocusedTextContextProvider(value: "foo", caretIndex: 3)
        let injector = DictationInjectionController(
            eventPoster: poster,
            coalescer: coalescer,
            focusedTextContextProvider: provider,
            frontmostAppProvider: { "com.apple.TextEdit" },
            bundleIdentifier: "com.floxbox.app",
        )

        injector.startSession()
        injector.apply(text: "hello")
        injector.apply(text: "hello world")

        XCTAssertEqual(poster.inserted, [" hello", " world"])
    }

    func testPrefixDeterminedAfterInitialEmptyUpdate() {
        let poster = TestEventPoster()
        let coalescer = ImmediateCoalescer()
        let provider = TestFocusedTextContextProvider(value: "foo", caretIndex: 3)
        let injector = DictationInjectionController(
            eventPoster: poster,
            coalescer: coalescer,
            focusedTextContextProvider: provider,
            frontmostAppProvider: { "com.apple.TextEdit" },
            bundleIdentifier: "com.floxbox.app",
        )

        injector.startSession()
        injector.apply(text: "")
        injector.apply(text: "hello")

        XCTAssertEqual(poster.inserted, [" hello"])
    }

    func testFallbackPrefixUsesPreviousSessionWhenNoContext() {
        let poster = TestEventPoster()
        let coalescer = ImmediateCoalescer()
        let provider = NilFocusedTextContextProvider()
        let injector = DictationInjectionController(
            eventPoster: poster,
            coalescer: coalescer,
            focusedTextContextProvider: provider,
            frontmostAppProvider: { "com.apple.TextEdit" },
            bundleIdentifier: "com.floxbox.app",
        )

        injector.startSession()
        injector.apply(text: "hello")
        _ = injector.finishSession()

        injector.startSession()
        injector.apply(text: "world")

        XCTAssertEqual(poster.inserted, ["hello", " world"])
    }

    func testFrontmostIsFloxBoxMarksFailure() {
        let poster = TestEventPoster()
        let coalescer = ImmediateCoalescer()
        let injector = DictationInjectionController(
            eventPoster: poster,
            coalescer: coalescer,
            frontmostAppProvider: { "com.floxbox.app" },
            bundleIdentifier: "com.floxbox.app",
        )

        injector.startSession()
        injector.apply(text: "hello")
        let result = injector.finishSession()

        XCTAssertTrue(result.requiresClipboardFallback)
        XCTAssertEqual(poster.inserted, [])
    }
}

private struct TestFocusedTextContextProvider: FocusedTextContextProviding {
    let value: String
    let caretIndex: Int

    func focusedTextContext() -> FocusedTextContext? {
        FocusedTextContext(value: value, caretIndex: caretIndex)
    }
}

private struct NilFocusedTextContextProvider: FocusedTextContextProviding {
    func focusedTextContext() -> FocusedTextContext? {
        nil
    }
}

private final class TestEventPoster: DictationEventPosting {
    var backspaceCount = 0
    var inserted: [String] = []

    func postBackspaces(_ count: Int) -> Bool {
        backspaceCount += count
        return true
    }

    func postText(_ text: String) -> Bool {
        inserted.append(text)
        return true
    }
}

private final class ImmediateCoalescer: DictationUpdateCoalescing {
    func enqueue(_ text: String, flush: @escaping (String) -> Void) { flush(text) }
    func flush() {}
    func cancel() {}
}
