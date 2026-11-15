// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "unity_levelplay_mediation",
    platforms: [.iOS(.v12)],
    products: [
        .library(name: "unity-levelplay-mediation", targets: ["unity_levelplay_mediation"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(url: "https://github.com/ironsource-mobile/LevelPlay-Swift-Package", exact: "9.4.0")
    ],
    targets: [
        .target(
            name: "unity_levelplay_mediation",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "UnityMediationSDK", package: "LevelPlay-Swift-Package")
            ],
            resources: [.process("Resources")],
            publicHeadersPath: "include"
        )
    ]
)
