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
        )
    ],
    targets: [
        .target(
            name: "EnterCalcCore",
            path: "src/shared",
            exclude: [
                "Resources/EnterCalc.icon",
                "Resources/EnterCalc-1024x1024.psd"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "EnterCalcCoreTests",
            dependencies: ["EnterCalcCore"],
            path: "tests",
            exclude: ["logs"]
        )
    ]
)
