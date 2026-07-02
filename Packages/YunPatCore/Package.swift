// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "YunPatCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "YunPatCore", targets: ["YunPatCore"])
    ],
    dependencies: [
        .package(path: "../YunPatNetworking"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.3"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "0.1.24")
    ],
    targets: [
        .target(
            name: "YunPatCore",
    dependencies: [
        .product(name: "YunPatNetworking", package: "YunPatNetworking"),
        .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
        .product(name: "Transformers", package: "swift-transformers")
    ]
        ),
        .testTarget(name: "YunPatCoreTests", dependencies: ["YunPatCore"])
    ]
)
