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
        .package(path: "Packages/YunPatCore"),
        .package(path: "Packages/PatentClient"),
        .package(path: "Packages/YunPatDesktop"),
        .package(path: "Packages/YunPatPlugins"),
        .package(path: "Packages/YunPatSandbox")
    ],
    targets: [
        .executableTarget(
            name: "YunPatApp",
            dependencies: [
                .product(name: "YunPatNetworking", package: "YunPatNetworking"),
                .product(name: "YunPatCore", package: "YunPatCore"),
                .product(name: "PatentClient", package: "PatentClient"),
                .product(name: "YunPatDesktop", package: "YunPatDesktop"),
                .product(name: "YunPatPlugins", package: "YunPatPlugins"),
                .product(name: "YunPatSandbox", package: "YunPatSandbox")
            ],
            path: "App"
        )
    ]
)
