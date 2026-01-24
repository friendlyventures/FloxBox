import Foundation

public enum TranscriptionModel: String, CaseIterable, Identifiable {
    case gpt4oTranscribe = "gpt-4o-transcribe"
    case gpt4oTranscribeLatest = "gpt-4o-transcribe-latest"
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"
    case gpt4oMiniTranscribe20251215 = "gpt-4o-mini-transcribe-2025-12-15"
    case whisper1 = "whisper-1"

    public static let defaultModel: TranscriptionModel = .gpt4oTranscribe

    public var id: String { rawValue }

    public var displayName: String { rawValue }
}
