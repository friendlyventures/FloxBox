import Foundation

public enum NoiseReductionOption: String, CaseIterable, Identifiable {
    case off
    case nearField
    case farField

    public static let defaultOption: NoiseReductionOption = .farField

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off:
            "Off"
        case .nearField:
            "Near Field"
        case .farField:
            "Far Field"
        }
    }

    public var setting: InputAudioNoiseReduction? {
        switch self {
        case .off:
            nil
        case .nearField:
            .nearField
        case .farField:
            .farField
        }
    }
}
