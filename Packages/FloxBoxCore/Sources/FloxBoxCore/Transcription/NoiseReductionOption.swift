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
            return "Off"
        case .nearField:
            return "Near Field"
        case .farField:
            return "Far Field"
        }
    }

    public var setting: InputAudioNoiseReduction? {
        switch self {
        case .off:
            return nil
        case .nearField:
            return .nearField
        case .farField:
            return .farField
        }
    }
}
