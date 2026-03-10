// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "wizmac",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "WizmacCore", targets: ["WizmacCore"]),
        .library(name: "WizmacSystem", targets: ["WizmacSystem"]),
        .library(name: "WizmacTextMode", targets: ["WizmacTextMode"]),
        .library(name: "WizmacControlPlane", targets: ["WizmacControlPlane"]),
        .library(name: "WizmacFixtureHostSupport", targets: ["WizmacFixtureHostSupport"]),
        .executable(name: "wizmac", targets: ["WizmacCLI"]),
        .executable(name: "WizmacService", targets: ["WizmacService"]),
        .executable(name: "WizmacMenuBarApp", targets: ["WizmacMenuBarApp"]),
        .executable(name: "WizmacFixtureHost", targets: ["WizmacFixtureHost"]),
    ],
    targets: [
        .target(
            name: "WizmacCore"
        ),
        .target(
            name: "WizmacTextMode",
            dependencies: ["WizmacCore"]
        ),
        .target(
            name: "WizmacSystem",
            dependencies: ["WizmacCore", "WizmacTextMode"]
        ),
        .target(
            name: "WizmacControlPlane",
            dependencies: ["WizmacCore", "WizmacSystem"]
        ),
        .executableTarget(
            name: "WizmacCLI",
            dependencies: ["WizmacCore", "WizmacSystem", "WizmacControlPlane"]
        ),
        .executableTarget(
            name: "WizmacService",
            dependencies: ["WizmacCore", "WizmacSystem", "WizmacControlPlane"]
        ),
        .executableTarget(
            name: "WizmacMenuBarApp",
            dependencies: ["WizmacCore", "WizmacSystem", "WizmacControlPlane"]
        ),
        .target(
            name: "WizmacFixtureHostSupport",
            dependencies: [],
            path: "Sources/WizmacFixtureHostSupport"
        ),
        .executableTarget(
            name: "WizmacFixtureHost",
            dependencies: [],
            path: "Sources/WizmacFixtureHost"
        ),
        .testTarget(
            name: "WizmacCoreTests",
            dependencies: ["WizmacCore"]
        ),
        .testTarget(
            name: "WizmacTextModeTests",
            dependencies: ["WizmacTextMode"]
        ),
        .testTarget(
            name: "WizmacSystemTests",
            dependencies: ["WizmacSystem"]
        ),
        .testTarget(
            name: "WizmacControlPlaneTests",
            dependencies: ["WizmacControlPlane"]
        ),
        .testTarget(
            name: "WizmacAppTests",
            dependencies: ["WizmacMenuBarApp", "WizmacFixtureHostSupport"]
        ),
    ]
)
