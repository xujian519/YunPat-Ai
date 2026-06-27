// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "YunPatCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "YunPatCore", targets: ["YunPatCore"]),
    ],
    dependencies: [
        .package(path: "../YunPatNetworking"),
    ],
    targets: [
        .target(
            name: "YunPatCore",
            dependencies: [.product(name: "YunPatNetworking", package: "YunPatNetworking")]
        ),
        .testTarget(name: "YunPatCoreTests", dependencies: ["YunPatCore"]),
    ]
)
