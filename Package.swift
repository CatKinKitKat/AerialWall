// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AerialWall",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "AerialWallKit", targets: ["AerialWallKit"]),
        .executable(name: "AerialWall", targets: ["AerialWall"]),
        .executable(name: "AerialWallAgent", targets: ["AerialWallAgent"]),
    ],
    targets: [
        .target(name: "AerialWallKit"),
        .executableTarget(
            name: "AerialWall",
            dependencies: ["AerialWallKit"],
            resources: [.process("Resources")]
        ),
        .executableTarget(name: "AerialWallAgent", dependencies: ["AerialWallKit"]),
        .testTarget(name: "AerialWallKitTests", dependencies: ["AerialWallKit"]),
    ]
)
