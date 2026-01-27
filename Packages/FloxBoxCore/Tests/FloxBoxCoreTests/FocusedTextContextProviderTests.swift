import ApplicationServices
@testable import FloxBoxCore
import XCTest

final class FocusedTextContextProviderTests: XCTestCase {
    func testProviderReturnsNilWhenNotTrusted() {
        let provider = AXFocusedTextContextProvider(isTrusted: { false })
        XCTAssertNil(provider.focusedTextContext())
    }

    func testProviderFallsBackToAppElementWhenSystemLookupFails() {
        let systemElement = AXUIElementCreateSystemWide()
        let appElement = AXUIElementCreateApplication(123)
        var focusedRoots: [AXUIElement] = []
        let provider = AXFocusedTextContextProvider(
            systemElement: systemElement,
            isTrusted: { true },
            frontmostPIDProvider: { 123 },
            applicationElementProvider: { _ in appElement },
            focusedElementProvider: { root in
                focusedRoots.append(root)
                if CFEqual(root, systemElement) { return nil }
                if CFEqual(root, appElement) { return appElement }
                return nil
            },
            valueProvider: { _ in "foo" },
            rangeProvider: { _ in CFRange(location: 3, length: 0) },
            secureElementProvider: { _ in false },
        )

        let context = provider.focusedTextContext()
        XCTAssertEqual(context, FocusedTextContext(value: "foo", caretIndex: 3))
        XCTAssertEqual(focusedRoots.count, 2)
    }

    func testProviderFallsBackToFocusedWindowWhenAppLookupFails() {
        let systemElement = AXUIElementCreateSystemWide()
        let appElement = AXUIElementCreateApplication(123)
        let windowElement = AXUIElementCreateApplication(456)
        var focusedRoots: [AXUIElement] = []
        let provider = AXFocusedTextContextProvider(
            systemElement: systemElement,
            isTrusted: { true },
            frontmostPIDProvider: { 123 },
            applicationElementProvider: { _ in appElement },
            focusedElementProvider: { root in
                focusedRoots.append(root)
                if CFEqual(root, systemElement) { return nil }
                if CFEqual(root, appElement) { return nil }
                if CFEqual(root, windowElement) { return appElement }
                return nil
            },
            focusedWindowProvider: { root in
                if CFEqual(root, appElement) { return windowElement }
                return nil
            },
            valueProvider: { _ in "foo" },
            rangeProvider: { _ in CFRange(location: 3, length: 0) },
            secureElementProvider: { _ in false },
        )

        let context = provider.focusedTextContext()
        XCTAssertEqual(context, FocusedTextContext(value: "foo", caretIndex: 3))
        XCTAssertEqual(focusedRoots.count, 3)
    }
}
