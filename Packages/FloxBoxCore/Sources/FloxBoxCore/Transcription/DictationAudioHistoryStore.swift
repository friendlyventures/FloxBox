import Foundation

public struct DictationSessionRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var startedAt: Date
    public var endedAt: Date?
    public var chunks: [DictationChunkRecord]

    public init(id: String, startedAt: Date, endedAt: Date?, chunks: [DictationChunkRecord]) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.chunks = chunks
    }
}

public struct DictationChunkRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var createdAt: Date
    public var wavPath: String
    public var byteCount: Int
    public var transcript: String

    public init(id: String, createdAt: Date, wavPath: String, byteCount: Int, transcript: String) {
        self.id = id
        self.createdAt = createdAt
        self.wavPath = wavPath
        self.byteCount = byteCount
        self.transcript = transcript
    }
}

public final class DictationAudioHistoryStore {
    private let rootURL: URL
    private let indexURL: URL
    private let fileManager: FileManager
    private let maxSessions: Int

    public init(
        baseURL: URL = DictationAudioHistoryStore.defaultBaseURL(),
        fileManager: FileManager = .default,
        maxSessions: Int = 5,
    ) {
        rootURL = baseURL
        indexURL = baseURL.appendingPathComponent("history.json")
        self.fileManager = fileManager
        self.maxSessions = maxSessions
    }

    public var baseURL: URL {
        rootURL
    }

    public func load() throws -> [DictationSessionRecord] {
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        let data = try Data(contentsOf: indexURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sessions = try decoder.decode([DictationSessionRecord].self, from: data)
        return sanitizeSessions(sessions)
    }

    public func save(_ sessions: [DictationSessionRecord]) throws {
        let trimmed = trimSessions(sessions)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: nil)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(trimmed)
        try data.write(to: indexURL, options: .atomic)
        removeStaleSessions(keeping: trimmed)
    }

    public func sessionURL(sessionID: String) -> URL {
        rootURL.appendingPathComponent(sessionID, isDirectory: true)
    }

    public func chunkURL(sessionID: String, fileName: String) -> URL {
        sessionURL(sessionID: sessionID).appendingPathComponent(fileName)
    }

    public func absoluteURL(for chunk: DictationChunkRecord) -> URL {
        rootURL.appendingPathComponent(chunk.wavPath)
    }

    public static func defaultBaseURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("FloxBox", isDirectory: true)
            .appendingPathComponent("Debug", isDirectory: true)
            .appendingPathComponent("DictationHistory", isDirectory: true)
    }

    private func sanitizeSessions(_ sessions: [DictationSessionRecord]) -> [DictationSessionRecord] {
        let trimmed = trimSessions(sessions)
        return trimmed.map { session in
            var cleaned = session
            cleaned.chunks = session.chunks.filter { chunk in
                fileManager.fileExists(atPath: absoluteURL(for: chunk).path)
            }
            return cleaned
        }
    }

    private func trimSessions(_ sessions: [DictationSessionRecord]) -> [DictationSessionRecord] {
        let sorted = sessions.sorted { $0.startedAt > $1.startedAt }
        if sorted.count <= maxSessions {
            return sorted
        }
        return Array(sorted.prefix(maxSessions))
    }

    private func removeStaleSessions(keeping sessions: [DictationSessionRecord]) {
        let keepIDs = Set(sessions.map(\.id))
        guard let contents = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
        ) else { return }

        for url in contents {
            guard url.lastPathComponent != "history.json" else { continue }
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues?.isDirectory == true else { continue }
            if !keepIDs.contains(url.lastPathComponent) {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}
