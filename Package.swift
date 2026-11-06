// swift-tools-version: 6.0
import PackageDescription

// Xcode 27（Swift 6 编译器 / macOS 27 SDK）可直接打开本文件编译运行。
// 语言模式显式固定为 v5：本工程网络层是 Pi-Star 同款的「串行队列 + 回调」模型，
// 迁移到 Swift 6 严格并发需要把 HomebrewClient / CallTracker 改成 actor（见 README）。
let swiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "PiStarBrandMeister",
    platforms: [.macOS(.v15)],
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
