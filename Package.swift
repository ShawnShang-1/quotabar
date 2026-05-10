// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "QuotaBar",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "QuotaBar", targets: ["QuotaBarApp"]),
        .library(name: "QuotaBarCore", targets: ["QuotaBarCore"]),
        .library(name: "QuotaBarProxy", targets: ["QuotaBarProxy"])
    ],
    targets: [
        .target(name: "QuotaBarCore"),
        .target(
            name: "QuotaBarProxy",
            dependencies: ["QuotaBarCore"]
        ),
        .executableTarget(
            name: "QuotaBarApp",
            dependencies: [
                "QuotaBarCore",
                "QuotaBarProxy"
            ]
        ),
        .testTarget(
            name: "QuotaBarCoreTests",
            dependencies: ["QuotaBarCore"]
        ),
        .testTarget(
            name: "QuotaBarProxyTests",
            dependencies: [
                "QuotaBarCore",
                "QuotaBarProxy"
            ]
        ),
        .testTarget(
            name: "QuotaBarPackagingTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
