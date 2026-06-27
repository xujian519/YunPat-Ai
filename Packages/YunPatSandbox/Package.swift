// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "YunPatSandbox",
    platforms: [.macOS(.v15)],
    products: [.library(name: "YunPatSandbox", targets: ["YunPatSandbox"])],
    targets: [
        .target(name: "YunPatSandbox"),
        .testTarget(name: "YunPatSandboxTests", dependencies: ["YunPatSandbox"]),
    ]
)
