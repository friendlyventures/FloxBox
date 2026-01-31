import Foundation

extension TranscriptionViewModel {
    var isRecording: Bool {
        status == .recording
    }

    func refreshInputDevices() {
        availableInputDevices = AudioInputDeviceProvider.availableDevices()
    }
}
