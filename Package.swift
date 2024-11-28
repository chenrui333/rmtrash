// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "rmtrash",
    platforms: [
        .macOS(.v10_10)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    products: [
        .executable(name: "rmtrash", targets: ["rmtrash"]),
    ],
    targets: [
        .executableTarget(
            name: "rmtrash",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]),
    ]
)
