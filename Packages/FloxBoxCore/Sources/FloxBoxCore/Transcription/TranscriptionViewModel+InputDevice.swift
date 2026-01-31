import CoreAudio

extension TranscriptionViewModel {
    func effectiveInputDeviceID() -> AudioDeviceID? {
        if let selectedInputDeviceID {
            return selectedInputDeviceID
        }
        if laptopOpenChecker(), let builtIn = builtInMicProvider() {
            return builtIn
        }
        return nil
    }
}
