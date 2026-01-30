import Foundation

public enum RecordingStatus: Equatable {
    case idle
    case connecting
    case recording
    case awaitingNetwork
    case error(String)

    public var label: String {
        switch self {
        case .idle:
            "Idle"
        case .connecting:
            "Connecting"
        case .recording:
            "Recording"
        case .awaitingNetwork:
            "Awaiting Network"
        case .error:
            "Error"
        }
    }
}

public enum APIKeyStatus: Equatable {
    case idle
    case saved
    case cleared
    case error(String)

    public var message: String? {
        switch self {
        case .idle:
            nil
        case .saved:
            "Saved"
        case .cleared:
            "Cleared"
        case let .error(message):
            message
        }
    }
}

public enum FormattingStatus: Equatable {
    case idle
    case formatting(attempt: Int, maxAttempts: Int)
    case failed(String)
    case completed

    public var label: String {
        switch self {
        case .idle:
            "Idle"
        case let .formatting(attempt, maxAttempts):
            "Formatting (\(attempt)/\(maxAttempts))"
        case .failed:
            "Failed"
        case .completed:
            "Completed"
        }
    }
}
