import SwiftUI

public struct ContentView: View {
    private let configuration: FloxBoxDistributionConfiguration

    public init(configuration: FloxBoxDistributionConfiguration) {
        self.configuration = configuration
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
            Text(configuration.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
