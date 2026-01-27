import SwiftUI

public struct ContentView: View {
    @State private var model: FloxBoxAppModel

    public init(configuration: FloxBoxDistributionConfiguration) {
        _model = State(initialValue: FloxBoxAppModel(configuration: configuration))
    }

    public var body: some View {
        DebugPanelView(model: model)
    }
}
