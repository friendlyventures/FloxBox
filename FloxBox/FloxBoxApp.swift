//
//  FloxBoxApp.swift
//  FloxBox
//
//  Created by Shayne Sweeney on 1/24/26.
//

import FloxBoxCore
import SwiftUI
#if !APP_STORE
    import FloxBoxCoreDirect
#endif

@main
@MainActor
struct FloxBoxApp: App {
    @State private var model: FloxBoxAppModel

    init() {
        let configuration: FloxBoxDistributionConfiguration
        #if APP_STORE
            configuration = .appStore
        #else
            configuration = FloxBoxDirectServices.configuration()
        #endif
        let model = FloxBoxAppModel(configuration: configuration)
        model.start()
        _model = State(initialValue: model)
    }

    var body: some Scene {
        FloxBoxAppRoot.makeScene(model: model)
    }
}
