// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "YunPatNetworking",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "YunPatNetworking", targets: ["YunPatNetworking"])
    ],
    targets: [
        .target(name: "YunPatNetworking"),
        .testTarget(name: "YunPatNetworkingTests", dependencies: ["YunPatNetworking"])
    ]
)
