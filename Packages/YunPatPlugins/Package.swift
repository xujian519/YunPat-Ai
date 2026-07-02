// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "YunPatPlugins",
    platforms: [.macOS(.v15)],
    products: [.library(name: "YunPatPlugins", targets: ["YunPatPlugins"])],
    dependencies: [
        .package(path: "../YunPatCore")
    ],
    targets: [
        .target(
            name: "YunPatPlugins",
            dependencies: [
                .product(name: "YunPatCore", package: "YunPatCore")
            ]),
        .testTarget(name: "YunPatPluginsTests", dependencies: ["YunPatPlugins"])
    ]
)
