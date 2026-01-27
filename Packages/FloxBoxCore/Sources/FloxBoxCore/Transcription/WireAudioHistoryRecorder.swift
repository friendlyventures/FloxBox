import Foundation

public actor WireAudioHistoryRecorder {
    private let store: DictationAudioHistoryStore
    private var sessions: [DictationSessionRecord]
    private var activeSessionID: String?
    private var activeChunkWriter: WavFileWriter?
    private var activeChunkFileName: String?
    private var activeChunkByteCount: Int = 0
    private var activeChunkIndex: Int = 0

    public init(store: DictationAudioHistoryStore) {
        self.store = store
        sessions = (try? store.load()) ?? []
    }

    public func sessionsSnapshot() -> [DictationSessionRecord] {
        sessions
    }

    public func startSession(sessionID: String, startedAt: Date) {
        activeSessionID = sessionID
        activeChunkWriter = nil
        activeChunkFileName = nil
        activeChunkByteCount = 0
        activeChunkIndex = 0

        upsertSession(
            DictationSessionRecord(
                id: sessionID,
                startedAt: startedAt,
                endedAt: nil,
                chunks: [],
            ),
        )
        persist()
    }

    public func appendSentAudio(_ data: Data) {
        guard !data.isEmpty, let sessionID = activeSessionID else { return }
        if activeChunkWriter == nil {
            startChunkWriter(sessionID: sessionID)
        }
        activeChunkWriter?.append(data)
        activeChunkByteCount += data.count
    }

    public func commit(itemId: String, createdAt: Date) {
        guard let sessionID = activeSessionID else { return }
        if activeChunkWriter == nil {
            startChunkWriter(sessionID: sessionID)
        }
        finalizeChunk(sessionID: sessionID, itemId: itemId, createdAt: createdAt)
    }

    public func updateTranscript(itemId: String, text: String) {
        for sessionIndex in sessions.indices {
            if let chunkIndex = sessions[sessionIndex].chunks.firstIndex(where: { $0.id == itemId }) {
                sessions[sessionIndex].chunks[chunkIndex].transcript = text
                persist()
                break
            }
        }
    }

    public func endSession(endedAt: Date) {
        guard let sessionID = activeSessionID else { return }
        if activeChunkWriter != nil {
            let fallbackId = "uncommitted-\(Int(endedAt.timeIntervalSince1970))"
            finalizeChunk(sessionID: sessionID, itemId: fallbackId, createdAt: endedAt)
        }
        if let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[sessionIndex].endedAt = endedAt
        }
        activeSessionID = nil
        activeChunkWriter = nil
        activeChunkFileName = nil
        activeChunkByteCount = 0
        activeChunkIndex = 0
        persist()
    }

    private func upsertSession(_ session: DictationSessionRecord) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
    }

    private func startChunkWriter(sessionID: String) {
        activeChunkIndex += 1
        let fileName = String(format: "chunk-%03d.wav", activeChunkIndex)
        let chunkURL = store.chunkURL(sessionID: sessionID, fileName: fileName)
        try? FileManager.default.createDirectory(
            at: chunkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil,
        )
        if let writer = try? WavFileWriter(url: chunkURL, sampleRate: 24000, channels: 1) {
            activeChunkWriter = writer
            activeChunkFileName = "\(sessionID)/\(fileName)"
            activeChunkByteCount = 0
        } else {
            activeChunkWriter = nil
            activeChunkFileName = nil
            activeChunkByteCount = 0
        }
    }

    private func finalizeChunk(sessionID: String, itemId: String, createdAt: Date) {
        defer {
            activeChunkWriter = nil
            activeChunkFileName = nil
            activeChunkByteCount = 0
        }

        try? activeChunkWriter?.finalize()
        guard let fileName = activeChunkFileName else { return }

        let chunk = DictationChunkRecord(
            id: itemId,
            createdAt: createdAt,
            wavPath: fileName,
            byteCount: activeChunkByteCount,
            transcript: "",
        )

        if let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[sessionIndex].chunks.append(chunk)
        }
        persist()
    }

    private func persist() {
        do {
            try store.save(sessions)
            sessions = (try? store.load()) ?? sessions
        } catch {
            return
        }
    }
}
