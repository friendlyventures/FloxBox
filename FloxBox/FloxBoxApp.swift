//
//  FloxBoxApp.swift
//  FloxBox
//
//  Created by Shayne Sweeney on 1/24/26.
//

import SwiftUI
import FloxBoxCore
#if !APP_STORE
import FloxBoxCoreDirect
#endif

@main
struct FloxBoxApp: App {
    private let configuration: FloxBoxDistributionConfiguration

    init() {
        #if APP_STORE
        configuration = .appStore
        #else
        configuration = FloxBoxDirectServices.configuration()
        #endif
    }

    var body: some Scene {
        FloxBoxAppRoot.makeScene(configuration: configuration)
    }
}
