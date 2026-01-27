@testable import FloxBoxCore
import XCTest

final class TranscriptStoreTests: XCTestCase {
    func testAppendFinalTextAddsNewFinalSegment() {
        let store = TranscriptStore()
        store.appendFinalText("Hello")
        XCTAssertEqual(store.displayText, "Hello")
    }

    func testOutOfOrderCompletionsUseCommitOrder() {
        let store = TranscriptStore()
        store.applyCommitted(.init(itemId: "item-1", previousItemId: nil))
        store.applyCommitted(.init(itemId: "item-2", previousItemId: "item-1"))

        store.applyCompleted(.init(itemId: "item-2", contentIndex: 0, transcript: "Second"))
        store.applyCompleted(.init(itemId: "item-1", contentIndex: 0, transcript: "First"))

        XCTAssertEqual(store.displayText, "First\nSecond")
    }

    func testDeltaThenCompletionReplacesText() {
        let store = TranscriptStore()
        store.applyCommitted(.init(itemId: "item-1", previousItemId: nil))
        store.applyDelta(.init(itemId: "item-1", contentIndex: 0, delta: "Hel"))
        store.applyDelta(.init(itemId: "item-1", contentIndex: 0, delta: "lo"))
        XCTAssertEqual(store.displayText, "Hello")

        store.applyCompleted(.init(itemId: "item-1", contentIndex: 0, transcript: "Hello there"))
        XCTAssertEqual(store.displayText, "Hello there")
    }

    func testCommittedItemsWithoutPreviousIdPreserveArrivalOrder() {
        let store = TranscriptStore()
        store.applyCommitted(.init(itemId: "item-1", previousItemId: nil))
        store.applyCommitted(.init(itemId: "item-2", previousItemId: nil))

        store.applyCompleted(.init(itemId: "item-1", contentIndex: 0, transcript: "First"))
        store.applyCompleted(.init(itemId: "item-2", contentIndex: 0, transcript: "Second"))

        XCTAssertEqual(store.displayText, "First\nSecond")
    }
}
