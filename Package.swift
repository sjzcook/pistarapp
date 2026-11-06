// swift-tools-version: 6.0
import PackageDescription

let swiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "PiStarBrandMeister",
    platforms: [
        .iOS(.v17),
        .macOS(.v15)
    ],
    products: [
        .library(name: "BrandMeisterKit", targets: ["BrandMeisterKit"]),
        .executable(name: "bmwatch", targets: ["bmwatch"]),
        .executable(name: "BrandMeisterApp", targets: ["BrandMeisterApp"]),
    ],
    targets: [
        .target(name: "BrandMeisterKit", swiftSettings: swiftSettings),
        .executableTarget(name: "bmwatch",
                          dependencies: ["BrandMeisterKit"],
                          swiftSettings: swiftSettings),
        .executableTarget(name: "BrandMeisterApp",
                          dependencies: ["BrandMeisterKit"],
                          swiftSettings: swiftSettings),
        .testTarget(name: "BrandMeisterKitTests",
                    dependencies: ["BrandMeisterKit"],
                    swiftSettings: swiftSettings),
    ]
)
