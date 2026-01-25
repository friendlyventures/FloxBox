import SwiftUI

public struct FloxBoxDistributionConfiguration: Equatable {
    public let label: String
    public let updatesView: AnyView?
    public let onAppear: (() -> Void)?

    public init(
        label: String,
        updatesView: AnyView? = nil,
        onAppear: (() -> Void)? = nil,
    ) {
        self.label = label
        self.updatesView = updatesView
        self.onAppear = onAppear
    }

    public static let appStore = Self(label: "App Store")
    public static let direct = Self(label: "Direct")

    public static func == (
        lhs: FloxBoxDistributionConfiguration,
        rhs: FloxBoxDistributionConfiguration,
    ) -> Bool {
        lhs.label == rhs.label
    }
}
