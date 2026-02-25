// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "asc-client",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/aaronsky/asc-swift", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-certificates", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "asc-client",
            dependencies: [
                .product(name: "AppStoreConnect", package: "asc-swift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ]
        ),
    ]
)
