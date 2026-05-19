// swift-tools-version:5.9
// Package.swift
// Swift Package definition for EnterCalc SwiftUI app.
import PackageDescription

let package = Package(
    name: "EnterCalc",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "EnterCalcCore",
            targets: ["EnterCalcCore"]
        ),
        .executable(
            name: "EnterCalc-macOS",
            targets: ["EnterCalc-macOS"]
        ),
        .executable(
            name: "EnterCalc-iOS",
            targets: ["EnterCalc-iOS"]
        )
    ],
    targets: [
        .target(
            name: "EnterCalcCore",
            path: "src/shared",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "EnterCalc-macOS",
            dependencies: ["EnterCalcCore"],
            path: "apple/src/macOS"
        ),
        .executableTarget(
            name: "EnterCalc-iOS",
            dependencies: ["EnterCalcCore"],
            path: "apple/src/iOS",
            resources: [
                .copy("Settings.bundle")
            ]
        ),
        .testTarget(
            name: "EnterCalcCoreTests",
            dependencies: ["EnterCalcCore"],
            path: "tests"
        )
    ]
)
