import Foundation

public enum TranscriptionLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"
    case german = "de"

    public static let defaultLanguage: TranscriptionLanguage = .english

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english:
            return "English"
        case .spanish:
            return "Spanish"
        case .german:
            return "German"
        }
    }

    /// Other ISO-639-1 codes are also supported by the realtime transcription API
    /// (e.g., fr, it, pt, ja, zh). See OpenAI docs for the current full list.
    public var code: String { rawValue }
}
