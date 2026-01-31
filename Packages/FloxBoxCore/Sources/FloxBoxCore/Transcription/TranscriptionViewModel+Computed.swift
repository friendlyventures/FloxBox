import Foundation

extension TranscriptionViewModel {
    var isRecording: Bool {
        status == .recording
    }

    var dictationAudioHistoryBaseURL: URL {
        audioHistoryStore.baseURL
    }
}
