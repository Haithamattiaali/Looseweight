// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LooseweightKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LooseweightKit", targets: ["LooseweightKit"]),
        .executable(name: "lw-eval", targets: ["lw-eval"]),
    ],
    targets: [
        .target(
            name: "LooseweightKit",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "lw-eval",
            dependencies: ["LooseweightKit"]
        ),
        .testTarget(
            name: "LooseweightKitTests",
            dependencies: ["LooseweightKit"]
        ),
    ]
)
