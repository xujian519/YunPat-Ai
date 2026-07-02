// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "YunPatDesktop",
    platforms: [.macOS(.v15)],
    products: [.library(name: "YunPatDesktop", targets: ["YunPatDesktop"])],
    targets: [
        .target(name: "YunPatDesktop"),
        .testTarget(name: "YunPatDesktopTests", dependencies: ["YunPatDesktop"])
    ]
)
