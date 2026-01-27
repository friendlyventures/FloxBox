import AVFoundation

public struct MicrophonePermissionClient {
    public var authorizationStatus: () -> AVAuthorizationStatus
    public var requestAccess: () async -> Bool

    public init(
        authorizationStatus: @escaping () -> AVAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .audio)
        },
        requestAccess: @escaping () async -> Bool = {
            await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        },
    ) {
        self.authorizationStatus = authorizationStatus
        self.requestAccess = requestAccess
    }
}
