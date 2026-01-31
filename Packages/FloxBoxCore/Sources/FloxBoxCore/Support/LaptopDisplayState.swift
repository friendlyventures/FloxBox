import CoreGraphics

enum LaptopDisplayState {
    static func isLaptopOpen() -> Bool {
        var displayCount: UInt32 = 0
        let countStatus = CGGetActiveDisplayList(0, nil, &displayCount)
        guard countStatus == .success, displayCount > 0 else { return false }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        let status = CGGetActiveDisplayList(displayCount, &displays, &displayCount)
        guard status == .success else { return false }

        for displayID in displays.prefix(Int(displayCount)) {
            if CGDisplayIsBuiltin(displayID) != 0, CGDisplayIsActive(displayID) != 0 {
                return true
            }
        }
        return false
    }
}
