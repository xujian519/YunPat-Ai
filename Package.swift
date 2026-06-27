// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "YunPatAi",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "YunPatApp", targets: ["YunPatApp"]),
    ],
    dependencies: [
        .package(path: "Packages/YunPatNetworking"),
        .package(path: "Packages/YunPatCore"),
        .package(path: "Packages/YunPatDesktop"),
        .package(path: "Packages/YunPatPlugins"),
        .package(path: "Packages/YunPatSandbox"),
    ],
    targets: [
        .target(
            name: "YunPatApp",
            dependencies: [
                .product(name: "YunPatNetworking", package: "YunPatNetworking"),
                .product(name: "YunPatCore", package: "YunPatCore"),
            ],
            path: "App"
        ),
    ]
)
