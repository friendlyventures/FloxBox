import Foundation

public enum VADMode: String, CaseIterable, Identifiable {
    case off
    case server
    case semantic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .server:
            return "Server VAD"
        case .semantic:
            return "Semantic VAD"
        }
    }
}

public enum ManualCommitInterval: Equatable, CaseIterable, Identifiable {
    case off
    case seconds(Int)

    public static let options: [ManualCommitInterval] = [
        .off,
        .seconds(1),
        .seconds(2),
        .seconds(3),
        .seconds(4),
        .seconds(5),
    ]

    public static var allCases: [ManualCommitInterval] {
        options
    }

    public static let defaultInterval: ManualCommitInterval = .seconds(2)

    public var id: String { label }

    public var label: String {
        switch self {
        case .off:
            return "Off"
        case .seconds(let value):
            return "\(value)s"
        }
    }

    public var seconds: Int? {
        switch self {
        case .off:
            return nil
        case .seconds(let value):
            return value
        }
    }
}

public struct ServerVADTuning: Equatable {
    public var threshold: Double?
    public var prefixPaddingMs: Int?
    public var silenceDurationMs: Int?
    public var idleTimeoutMs: Int?

    public init(
        threshold: Double? = nil,
        prefixPaddingMs: Int? = nil,
        silenceDurationMs: Int? = nil,
        idleTimeoutMs: Int? = nil
    ) {
        self.threshold = threshold
        self.prefixPaddingMs = prefixPaddingMs
        self.silenceDurationMs = silenceDurationMs
        self.idleTimeoutMs = idleTimeoutMs
    }
}

public enum SemanticVADEagerness: String, CaseIterable, Identifiable {
    case low
    case medium
    case high
    case auto

    public var id: String { rawValue }

    public var displayName: String { rawValue }
}

public struct SemanticVADTuning: Equatable {
    public var eagerness: SemanticVADEagerness?

    public init(eagerness: SemanticVADEagerness? = nil) {
        self.eagerness = eagerness
    }
}
