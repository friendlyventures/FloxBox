import Foundation

public struct TranscriptionSessionConfiguration: Equatable {
    public var model: TranscriptionModel
    public var vadMode: VADMode
    public var serverVAD: ServerVADTuning
    public var semanticVAD: SemanticVADTuning

    public init(
        model: TranscriptionModel,
        vadMode: VADMode,
        serverVAD: ServerVADTuning,
        semanticVAD: SemanticVADTuning
    ) {
        self.model = model
        self.vadMode = vadMode
        self.serverVAD = serverVAD
        self.semanticVAD = semanticVAD
    }

    public var turnDetectionSetting: TurnDetectionSetting {
        switch vadMode {
        case .off:
            return .disabled
        case .server:
            return .server(serverVAD)
        case .semantic:
            return .semantic(semanticVAD)
        }
    }
}

public struct RealtimeTranscriptionSessionUpdate: Encodable, Equatable {
    public let type: String = "session.update"
    public let session: Session

    public init(configuration: TranscriptionSessionConfiguration) {
        self.session = Session(
            audio: Audio(
                input: Input(
                    format: Format(type: "audio/pcm", rate: 24_000),
                    transcription: Transcription(model: configuration.model.rawValue),
                    turnDetection: configuration.turnDetectionSetting
                )
            ),
            include: ["item.input_audio_transcription.logprobs"]
        )
    }

    public struct Session: Encodable, Equatable {
        public let audio: Audio
        public let include: [String]?
    }

    public struct Audio: Encodable, Equatable {
        public let input: Input
    }

    public struct Input: Encodable, Equatable {
        public let format: Format
        public let transcription: Transcription
        public let turnDetection: TurnDetectionSetting

        enum CodingKeys: String, CodingKey {
            case format
            case transcription
            case turnDetection = "turn_detection"
        }
    }

    public struct Format: Encodable, Equatable {
        public let type: String
        public let rate: Int
    }

    public struct Transcription: Encodable, Equatable {
        public let model: String
    }
}

public enum TurnDetectionSetting: Encodable, Equatable {
    case disabled
    case server(ServerVADTuning)
    case semantic(SemanticVADTuning)

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .disabled:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .server(let tuning):
            try TurnDetectionPayload(
                type: "server_vad",
                threshold: tuning.threshold,
                prefixPaddingMs: tuning.prefixPaddingMs,
                silenceDurationMs: tuning.silenceDurationMs,
                idleTimeoutMs: tuning.idleTimeoutMs,
                eagerness: nil
            ).encode(to: encoder)
        case .semantic(let tuning):
            try TurnDetectionPayload(
                type: "semantic_vad",
                threshold: nil,
                prefixPaddingMs: nil,
                silenceDurationMs: nil,
                idleTimeoutMs: nil,
                eagerness: tuning.eagerness?.rawValue
            ).encode(to: encoder)
        }
    }
}

public struct TurnDetectionPayload: Encodable, Equatable {
    public let type: String
    public let threshold: Double?
    public let prefixPaddingMs: Int?
    public let silenceDurationMs: Int?
    public let idleTimeoutMs: Int?
    public let eagerness: String?

    enum CodingKeys: String, CodingKey {
        case type
        case threshold
        case prefixPaddingMs = "prefix_padding_ms"
        case silenceDurationMs = "silence_duration_ms"
        case idleTimeoutMs = "idle_timeout_ms"
        case eagerness
    }
}
