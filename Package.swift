// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "YunPatAi",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "YunPatAi", targets: ["YunPatApp"])
    ],
    dependencies: [
        .package(path: "Packages/YunPatNetworking"),
        .package(path: "Packages/YunPatCore")
    ],
    targets: [
        .executableTarget(
            name: "YunPatApp",
            dependencies: [
                .product(name: "YunPatNetworking", package: "YunPatNetworking"),
                .product(name: "YunPatCore", package: "YunPatCore")
            ],
            path: "App"
        )
    ]
)
