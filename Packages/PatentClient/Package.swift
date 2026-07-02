// swift-tools-version:6.0
import PackageDescription

let package: Package = Package(
    name: "PatentClient",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PatentClient", targets: ["PatentClient"])
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0")
    ],
    targets: [
        .target(
            name: "PatentClient",
            dependencies: ["SwiftSoup"]
        ),
        .testTarget(
            name: "PatentClientTests",
            dependencies: ["PatentClient"]
        )
    ]
)
