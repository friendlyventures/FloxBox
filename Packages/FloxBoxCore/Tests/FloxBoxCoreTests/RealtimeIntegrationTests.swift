import Foundation
import XCTest
@testable import FloxBoxCore

final class RealtimeIntegrationTests: XCTestCase {
    func testRealtimeTranscriptionFromFixture() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["FLOXBOX_RUN_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("Set FLOXBOX_RUN_INTEGRATION_TESTS=1 to run integration tests.")
        }
        guard let apiKey = environment["OPENAI_API_KEY"], !apiKey.isEmpty else {
            throw XCTSkip("Set OPENAI_API_KEY to run integration tests.")
        }

        let fixtureURL = try XCTUnwrap(Bundle.module.url(forResource: "test123", withExtension: "wav"))
        let wavData = try Data(contentsOf: fixtureURL)
        let wavFile = try WAVFile(data: wavData)

        XCTAssertEqual(wavFile.format.sampleRate, 24_000)
        XCTAssertEqual(wavFile.format.channels, 1)
        XCTAssertEqual(wavFile.format.bitsPerSample, 16)
        XCTAssertFalse(wavFile.pcmData.isEmpty)

        let client = RealtimeWebSocketClient(apiKey: apiKey)
        client.connect()
        defer { client.close() }

        let configuration = TranscriptionSessionConfiguration(
            model: .defaultModel,
            vadMode: .off,
            serverVAD: .init(),
            semanticVAD: .init()
        )
        try await client.sendSessionUpdate(RealtimeTranscriptionSessionUpdate(configuration: configuration))

        for chunk in wavFile.pcmData.chunked(into: 3200) {
            try await client.sendAudio(chunk)
        }
        try await client.commitAudio()

        let transcript = try await awaitTranscript(from: client.events, timeoutSeconds: 20)
        XCTAssertFalse(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

private enum IntegrationTestError: Error {
    case timedOut
    case serverError(String)
    case noTranscript
}

private func awaitTranscript(
    from events: AsyncStream<RealtimeServerEvent>,
    timeoutSeconds: UInt64
) async throws -> String {
    try await withThrowingTaskGroup(of: String.self) { group in
        group.addTask {
            var collected = ""
            for await event in events {
                switch event {
                case .transcriptionDelta(let delta):
                    collected.append(delta.delta)
                case .transcriptionCompleted(let completed):
                    if !completed.transcript.isEmpty {
                        return completed.transcript
                    }
                    if !collected.isEmpty {
                        return collected
                    }
                case .error(let message):
                    throw IntegrationTestError.serverError(message)
                case .inputAudioCommitted, .unknown:
                    continue
                }
            }

            if !collected.isEmpty {
                return collected
            }
            throw IntegrationTestError.noTranscript
        }

        group.addTask {
            try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
            throw IntegrationTestError.timedOut
        }

        guard let result = try await group.next() else {
            throw IntegrationTestError.noTranscript
        }
        group.cancelAll()
        return result
    }
}

private struct WAVFile {
    struct Format {
        let sampleRate: Int
        let channels: Int
        let bitsPerSample: Int
    }

    let format: Format
    let pcmData: Data

    init(data: Data) throws {
        guard data.count >= 12 else {
            throw WAVError.invalidHeader
        }
        guard data.asciiString(in: 0..<4) == "RIFF" else {
            throw WAVError.invalidHeader
        }
        guard data.asciiString(in: 8..<12) == "WAVE" else {
            throw WAVError.invalidHeader
        }

        var format: Format?
        var pcmData: Data?
        var offset = 12

        while offset + 8 <= data.count {
            let chunkID = data.asciiString(in: offset..<(offset + 4))
            let chunkSize = Int(data.uint32LE(at: offset + 4))
            let chunkStart = offset + 8
            let chunkEnd = chunkStart + chunkSize
            guard chunkEnd <= data.count else {
                break
            }

            if chunkID == "fmt " {
                let audioFormat = data.uint16LE(at: chunkStart)
                let channels = Int(data.uint16LE(at: chunkStart + 2))
                let sampleRate = Int(data.uint32LE(at: chunkStart + 4))
                let bitsPerSample = Int(data.uint16LE(at: chunkStart + 14))
                guard audioFormat == 1 else {
                    throw WAVError.unsupportedFormat
                }
                format = Format(sampleRate: sampleRate, channels: channels, bitsPerSample: bitsPerSample)
            } else if chunkID == "data" {
                pcmData = data.subdata(in: chunkStart..<chunkEnd)
            }

            offset = chunkEnd + (chunkSize % 2)
        }

        guard let resolvedFormat = format, let resolvedData = pcmData else {
            throw WAVError.missingData
        }
        self.format = resolvedFormat
        self.pcmData = resolvedData
    }
}

private enum WAVError: Error {
    case invalidHeader
    case unsupportedFormat
    case missingData
}

private extension Data {
    func asciiString(in range: Range<Int>) -> String {
        String(bytes: self[range], encoding: .ascii) ?? ""
    }

    func uint16LE(at offset: Int) -> UInt16 {
        let slice = self[offset..<(offset + 2)]
        return UInt16(slice[slice.startIndex]) | UInt16(slice[slice.startIndex + 1]) << 8
    }

    func uint32LE(at offset: Int) -> UInt32 {
        let slice = self[offset..<(offset + 4)]
        return UInt32(slice[slice.startIndex])
            | UInt32(slice[slice.startIndex + 1]) << 8
            | UInt32(slice[slice.startIndex + 2]) << 16
            | UInt32(slice[slice.startIndex + 3]) << 24
    }

    func chunked(into size: Int) -> [Data] {
        guard size > 0 else { return [] }
        var chunks: [Data] = []
        var offset = 0
        while offset < count {
            let end = Swift.min(offset + size, count)
            chunks.append(subdata(in: offset..<end))
            offset = end
        }
        return chunks
    }
}
