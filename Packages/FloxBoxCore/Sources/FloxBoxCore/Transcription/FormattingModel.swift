import Foundation

public enum FormattingModel: String, CaseIterable, Identifiable, Codable {
    case gpt5 = "gpt-5.2"
    case gpt5Mini = "gpt-5-mini"
    case gpt5Nano = "gpt-5-nano"

    public static let defaultModel: FormattingModel = .gpt5Nano

    public var id: String { rawValue }
    public var displayName: String { rawValue }

    public var reasoningEffort: String {
        switch self {
        case .gpt5:
            "none"
        case .gpt5Mini, .gpt5Nano:
            "minimal"
        }
    }
}
