public struct FloxBoxDistributionConfiguration: Equatable {
    public let label: String

    public init(label: String) {
        self.label = label
    }

    public static let appStore = Self(label: "App Store")
    public static let direct = Self(label: "Direct")
}
