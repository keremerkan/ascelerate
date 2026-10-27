// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ascelerate",
    platforms: [.macOS(.v15), .iOS("27.0")],
    products: [
        .executable(name: "ascelerate", targets: ["ascelerate"]),
        .library(name: "ASCKit", targets: ["ASCKit"]),
        .library(name: "AscelerateCore", targets: ["AscelerateCore"]),
        .library(name: "AscelerateAds", targets: ["AscelerateAds"]),
    ],
    dependencies: [
        // Apple Ads Platform API client. Its traits add swift-service-lifecycle and
        // swift-configuration, which a CLI doesn't need.
        .package(url: "https://github.com/apple/apple-ads-platform-api-swift", from: "1.109.0", traits: []),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-certificates", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto", from: "4.2.0"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "ascelerate",
            dependencies: [
                "ASCKit",
                "AscelerateCore",
                "AscelerateAds",
                .product(name: "AppleAdsClient", package: "apple-ads-platform-api-swift"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        // App Store Connect logic shared by the commands, free of terminal I/O: lookups that can
        // be ambiguous take a `choose` closure instead of prompting.
        .target(
            name: "AscelerateCore",
            dependencies: ["ASCKit", .product(name: "X509", package: "swift-certificates")]
        ),
        // Apple Ads logic, likewise free of terminal I/O. Its own target: AppleAdsClient and ASCKit
        // both generate top-level `Client`, `Components` and `Operations` types.
        .target(
            name: "AscelerateAds",
            dependencies: [
                "AscelerateCore",
                .product(name: "AppleAdsClient", package: "apple-ads-platform-api-swift"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ]
        ),
        .target(
            name: "ASCKit",
            dependencies: [
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ],
            // The generated client warns about every attribute and parameter Apple deprecated, from
            // its own Codable and query code. Our use of them still warns in the ascelerate target.
            swiftSettings: [.unsafeFlags(["-suppress-warnings"])],
            plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
        ),
        .testTarget(
            name: "ASCKitTests",
            dependencies: ["ASCKit"]
        ),
        .testTarget(
            name: "AscelerateCoreTests",
            dependencies: ["AscelerateCore"]
        ),
    ]
)
