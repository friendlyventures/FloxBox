@testable import FloxBoxCore
import XCTest

final class PersonalGlossaryStoreTests: XCTestCase {
    func testGlossaryPersistsEntries() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = PersonalGlossaryStore(userDefaults: defaults)
        let entry = PersonalGlossaryEntry(
            id: UUID(),
            term: "OpenAI",
            aliases: ["Open AI", "open ai"],
            notes: "Company name",
            isEnabled: true,
        )

        store.entries = [entry]

        let reloaded = PersonalGlossaryStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries.first?.term, "OpenAI")
        XCTAssertEqual(reloaded.activeEntries.count, 1)
    }

    func testGlossaryFiltersDisabledEntries() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = PersonalGlossaryStore(userDefaults: defaults)
        store.entries = [
            PersonalGlossaryEntry(term: "Foo", aliases: [], notes: nil, isEnabled: false),
            PersonalGlossaryEntry(term: "Bar", aliases: [], notes: nil, isEnabled: true),
        ]

        XCTAssertEqual(store.activeEntries.map(\.term), ["Bar"])
    }
}
