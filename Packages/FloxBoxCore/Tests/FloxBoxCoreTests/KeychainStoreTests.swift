@testable import FloxBoxCore
import XCTest

final class KeychainStoreTests: XCTestCase {
    func testInMemoryKeychainStoresValues() {
        let store = InMemoryKeychainStore()
        XCTAssertNil(try? store.load())

        XCTAssertNoThrow(try store.save("sk-test"))
        XCTAssertEqual(try store.load(), "sk-test")

        XCTAssertNoThrow(try store.delete())
        XCTAssertNil(try store.load())
    }
}

final class InMemoryKeychainStore: KeychainStoring {
    private var value: String?

    func load() throws -> String? {
        value
    }

    func save(_ value: String) throws {
        self.value = value
    }

    func delete() throws {
        value = nil
    }
}
