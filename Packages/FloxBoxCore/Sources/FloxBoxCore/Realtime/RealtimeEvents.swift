import Foundation

public enum RealtimeServerEvent: Equatable {
    case transcriptionDelta(TranscriptionDeltaEvent)
    case transcriptionCompleted(TranscriptionCompletedEvent)
    case inputAudioCommitted(InputAudioCommittedEvent)
    case error(String)
    case unknown(String)
}

public struct TranscriptionDeltaEvent: Decodable, Equatable {
    public let itemId: String
    public let contentIndex: Int
    public let delta: String

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case contentIndex = "content_index"
        case delta
    }
}

public struct TranscriptionCompletedEvent: Decodable, Equatable {
    public let itemId: String
    public let contentIndex: Int
    public let transcript: String

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case contentIndex = "content_index"
        case transcript
    }
}

public struct InputAudioCommittedEvent: Decodable, Equatable {
    public let itemId: String
    public let previousItemId: String?

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case previousItemId = "previous_item_id"
    }
}

public struct RealtimeErrorEvent: Decodable, Equatable {
    public struct ErrorDetail: Decodable, Equatable {
        public let message: String
    }

    public let error: ErrorDetail
}

private struct RealtimeEventEnvelope: Decodable {
    let type: String
}

public enum RealtimeEventDecoder {
    public static func decode(_ data: Data) throws -> RealtimeServerEvent {
        let envelope = try JSONDecoder().decode(RealtimeEventEnvelope.self, from: data)
        switch envelope.type {
        case "conversation.item.input_audio_transcription.delta":
            return .transcriptionDelta(try JSONDecoder().decode(TranscriptionDeltaEvent.self, from: data))
        case "conversation.item.input_audio_transcription.completed":
            return .transcriptionCompleted(try JSONDecoder().decode(TranscriptionCompletedEvent.self, from: data))
        case "input_audio_buffer.committed":
            return .inputAudioCommitted(try JSONDecoder().decode(InputAudioCommittedEvent.self, from: data))
        case "error":
            let error = try JSONDecoder().decode(RealtimeErrorEvent.self, from: data)
            return .error(error.error.message)
        default:
            return .unknown(envelope.type)
        }
    }
}
