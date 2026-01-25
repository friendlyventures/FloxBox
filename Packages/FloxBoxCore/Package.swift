// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FloxBoxCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FloxBoxCore", targets: ["FloxBoxCore"]),
        .library(name: "FloxBoxCoreDirect", targets: ["FloxBoxCoreDirect"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FloxBoxCore",
            path: "Sources/FloxBoxCore"
        ),
        .target(
            name: "FloxBoxCoreDirect",
            dependencies: ["FloxBoxCore"],
            path: "Sources/FloxBoxCoreDirect",
            swiftSettings: [
                .define("DIRECT_DISTRIBUTION"),
            ]
        ),
        .testTarget(
            name: "FloxBoxCoreTests",
            dependencies: ["FloxBoxCore"],
            path: "Tests/FloxBoxCoreTests",
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "FloxBoxCoreDirectTests",
            dependencies: ["FloxBoxCoreDirect"],
            path: "Tests/FloxBoxCoreDirectTests"
        ),
    ]
)
