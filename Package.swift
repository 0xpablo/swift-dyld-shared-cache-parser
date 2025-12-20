// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swift-dyld-shared-cache-parser",
    platforms: [
        .macOS(.v15), .iOS(.v18), .watchOS(.v11), .tvOS(.v18), .visionOS(.v2),
    ],
    products: [
        .library(name: "DyldSharedCacheParser", targets: ["DyldSharedCacheParser"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-binary-parsing",
            branch: "main"
        )
    ],
    targets: [
        .target(
            name: "DyldSharedCacheParser",
            dependencies: [
                .product(name: "BinaryParsing", package: "swift-binary-parsing")
            ],
            swiftSettings: [
                .enableExperimentalFeature("Lifetimes")
            ]
        ),
        .testTarget(
            name: "DyldSharedCacheParserTests",
            dependencies: ["DyldSharedCacheParser"],
            swiftSettings: [
                .enableExperimentalFeature("Lifetimes")
            ]
        )
    ]
)
