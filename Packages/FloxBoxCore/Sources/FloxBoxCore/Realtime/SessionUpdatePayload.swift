import Foundation

public struct TranscriptionSessionConfiguration: Equatable {
    public var model: TranscriptionModel
    public var language: TranscriptionLanguage
    public var noiseReduction: InputAudioNoiseReduction?
    public var vadMode: VADMode
    public var serverVAD: ServerVADTuning
    public var semanticVAD: SemanticVADTuning

    public init(
        model: TranscriptionModel,
        language: TranscriptionLanguage,
        noiseReduction: InputAudioNoiseReduction? = .farField,
        vadMode: VADMode,
        serverVAD: ServerVADTuning,
        semanticVAD: SemanticVADTuning
    ) {
        self.model = model
        self.language = language
        self.noiseReduction = noiseReduction
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
    public let type: String = "transcription_session.update"
    public let session: Session

    public init(configuration: TranscriptionSessionConfiguration) {
        self.session = Session(
            inputAudioFormat: "pcm16",
            inputAudioTranscription: Transcription(
                model: configuration.model.rawValue,
                language: configuration.language.code
            ),
            inputAudioNoiseReduction: configuration.noiseReduction,
            turnDetection: configuration.turnDetectionSetting,
            include: ["item.input_audio_transcription.logprobs"]
        )
    }

    public struct Transcription: Encodable, Equatable {
        public let model: String
        public let language: String
    }

    public struct Session: Encodable, Equatable {
        public let inputAudioFormat: String
        public let inputAudioTranscription: Transcription
        public let inputAudioNoiseReduction: InputAudioNoiseReduction?
        public let turnDetection: TurnDetectionSetting
        public let include: [String]?

        enum CodingKeys: String, CodingKey {
            case inputAudioFormat = "input_audio_format"
            case inputAudioTranscription = "input_audio_transcription"
            case inputAudioNoiseReduction = "input_audio_noise_reduction"
            case turnDetection = "turn_detection"
            case include
        }
    }
}

public enum InputAudioNoiseReductionType: String, Encodable, Equatable {
    case nearField = "near_field"
    case farField = "far_field"
}

public struct InputAudioNoiseReduction: Encodable, Equatable {
    public let type: InputAudioNoiseReductionType

    public static let nearField = InputAudioNoiseReduction(type: .nearField)
    public static let farField = InputAudioNoiseReduction(type: .farField)
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
