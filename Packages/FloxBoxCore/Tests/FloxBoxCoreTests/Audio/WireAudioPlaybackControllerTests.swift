@testable import FloxBoxCore
import XCTest

@MainActor
final class WireAudioPlaybackControllerTests: XCTestCase {
    func testPlayAllAdvancesActiveChunk() {
        let player = TestAudioPlayer()
        let controller = WireAudioPlaybackController(player: player)
        let session = DictationSessionRecord(
            id: "session-1",
            startedAt: Date(),
            endedAt: Date(),
            chunks: [
                DictationChunkRecord(id: "item-1", createdAt: Date(), wavPath: "a.wav", byteCount: 2, transcript: ""),
                DictationChunkRecord(id: "item-2", createdAt: Date(), wavPath: "b.wav", byteCount: 2, transcript: ""),
            ],
        )

        controller.playAll(session: session, baseURL: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(controller.activeChunkID, "item-1")

        player.finish()
        XCTAssertEqual(controller.activeChunkID, "item-2")

        player.finish()
        XCTAssertNil(controller.activeChunkID)
    }
}

@MainActor
private final class TestAudioPlayer: AudioPlaying {
    private var finishHandler: (() -> Void)?

    func play(url _: URL, onFinish: @escaping () -> Void) {
        finishHandler = onFinish
    }

    func stop() {
        finishHandler = nil
    }

    func finish() {
        finishHandler?()
    }
}
