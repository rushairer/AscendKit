// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "AscendKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AscendKitCore", targets: ["AscendKitCore"]),
        .executable(name: "ascendkit", targets: ["AscendKitCLI"])
    ],
    targets: [
        .target(name: "AscendKitCore"),
        .executableTarget(
            name: "AscendKitCLI",
            dependencies: ["AscendKitCore"]
        ),
        .testTarget(
            name: "AscendKitCoreTests",
            dependencies: ["AscendKitCore"]
        ),
        .testTarget(
            name: "AscendKitCLITests",
            dependencies: ["AscendKitCore"]
        )
    ]
)
