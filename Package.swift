// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Expirable",
    platforms: [
        .macOS("13.0"),
        .iOS("16.0"),
        .macCatalyst("16.0")
    ],
    products: [ 
        .library(
            name: "Expirable",
            targets: ["Expirable"]),
    ],
    dependencies: [
    ],
    targets: [ 
        .target(
            name: "Expirable",
            dependencies: [],
            path: "Sources"),
        .testTarget(
            name: "ExpirableTests",
            dependencies: ["Expirable"]),
    ]
)
