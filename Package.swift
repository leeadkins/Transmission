// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Transmission",
    platforms: [
        .iOS(.v13),
        .macCatalyst(.v13),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "Transmission",
            targets: ["Transmission"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/nathantannar4/Engine", from: "1.9.4"),
        .package(url: "https://github.com/nathantannar4/Turbocharger", from: "1.3.3"),
    ],
    targets: [
        .target(
            name: "Transmission",
            dependencies: [
                "Engine",
                "Turbocharger",
            ]
        )
    ]
)
