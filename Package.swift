// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ascelerate",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/aaronsky/asc-swift", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-certificates", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "ascelerate",
            dependencies: [
                .product(name: "AppStoreConnect", package: "asc-swift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
                .product(name: "Yams", package: "Yams"),
            ]
        ),
    ]
)
