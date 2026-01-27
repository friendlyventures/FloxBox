@testable import FloxBoxCore
import XCTest

final class DictationTextDiffTests: XCTestCase {
    func testInsertFromEmpty() {
        let diff = DictationTextDiff.diff(from: "", to: "hello")
        XCTAssertEqual(diff.backspaceCount, 0)
        XCTAssertEqual(diff.insertText, "hello")
    }

    func testDeleteSuffix() {
        let diff = DictationTextDiff.diff(from: "hello", to: "hel")
        XCTAssertEqual(diff.backspaceCount, 2)
        XCTAssertEqual(diff.insertText, "")
    }

    func testReplaceTail() {
        let diff = DictationTextDiff.diff(from: "hello world", to: "hello there")
        XCTAssertEqual(diff.backspaceCount, 5)
        XCTAssertEqual(diff.insertText, "there")
    }

    func testNoChange() {
        let diff = DictationTextDiff.diff(from: "same", to: "same")
        XCTAssertEqual(diff.backspaceCount, 0)
        XCTAssertEqual(diff.insertText, "")
    }
}
