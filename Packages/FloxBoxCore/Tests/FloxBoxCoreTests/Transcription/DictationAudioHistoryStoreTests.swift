@testable import FloxBoxCore
import XCTest

final class DictationAudioHistoryStoreTests: XCTestCase {
    func testStorePersistsAndLoadsSessions() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = DictationAudioHistoryStore(baseURL: base)

        let chunkURL = base.appendingPathComponent("session-1/chunk-001.wav")
        try FileManager.default.createDirectory(
            at: chunkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil,
        )
        FileManager.default.createFile(atPath: chunkURL.path, contents: Data([0x01]))

        let session = DictationSessionRecord(
            id: "session-1",
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            chunks: [DictationChunkRecord(
                id: "item-1",
                createdAt: Date(timeIntervalSince1970: 1.5),
                wavPath: "session-1/chunk-001.wav",
                byteCount: 4,
                transcript: "Hello",
            )],
        )

        try store.save([session])
        let loaded = try store.load()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, "session-1")
        XCTAssertEqual(loaded.first?.chunks.first?.transcript, "Hello")
    }

    func testStoreKeepsLastFiveSessions() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = DictationAudioHistoryStore(baseURL: base)

        let sessions = (1 ... 6).map { index in
            DictationSessionRecord(
                id: "session-\(index)",
                startedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                endedAt: nil,
                chunks: [],
            )
        }

        try store.save(sessions)
        let loaded = try store.load()

        XCTAssertEqual(loaded.count, 5)
        XCTAssertEqual(loaded.first?.id, "session-6")
        XCTAssertEqual(loaded.last?.id, "session-2")
    }
}
