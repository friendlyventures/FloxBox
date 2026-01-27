import AVFoundation
import Foundation
import Observation

@MainActor
public protocol AudioPlaying {
    func play(url: URL, onFinish: @escaping () -> Void)
    func stop()
}

@MainActor
final class AVAudioPlayerAdapter: NSObject, AudioPlaying, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var finishHandler: (() -> Void)?

    func play(url: URL, onFinish: @escaping () -> Void) {
        finishHandler = onFinish
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.play()
    }

    func stop() {
        player?.stop()
        player = nil
        finishHandler = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully _: Bool) {
        Task { @MainActor [weak self] in
            self?.handleFinish()
        }
    }

    private func handleFinish() {
        let handler = finishHandler
        finishHandler = nil
        handler?()
    }
}

@MainActor
@Observable
public final class WireAudioPlaybackController {
    public private(set) var activeSessionID: String?
    public private(set) var activeChunkID: String?
    public private(set) var isPlaying = false

    private let player: AudioPlaying
    private var queue: [QueuedChunk] = []

    private struct QueuedChunk {
        let sessionID: String
        let chunk: DictationChunkRecord
        let baseURL: URL
    }

    public init(player: AudioPlaying) {
        self.player = player
    }

    public convenience init() {
        self.init(player: AVAudioPlayerAdapter())
    }

    public func playAll(session: DictationSessionRecord, baseURL: URL) {
        queue = session.chunks.map { QueuedChunk(sessionID: session.id, chunk: $0, baseURL: baseURL) }
        activeSessionID = session.id
        playNext()
    }

    public func playChunk(session: DictationSessionRecord, chunk: DictationChunkRecord, baseURL: URL) {
        queue = [QueuedChunk(sessionID: session.id, chunk: chunk, baseURL: baseURL)]
        activeSessionID = session.id
        playNext()
    }

    public func stop() {
        queue.removeAll()
        activeSessionID = nil
        activeChunkID = nil
        isPlaying = false
        player.stop()
    }

    private func playNext() {
        guard !queue.isEmpty else {
            activeChunkID = nil
            activeSessionID = nil
            isPlaying = false
            return
        }

        let next = queue.removeFirst()
        activeSessionID = next.sessionID
        activeChunkID = next.chunk.id
        isPlaying = true

        let url = next.baseURL.appendingPathComponent(next.chunk.wavPath)
        player.play(url: url) { [weak self] in
            guard let self else { return }
            playNext()
        }
    }
}
