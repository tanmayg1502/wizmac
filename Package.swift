// swift-tools-version: 6.2

import PackageDescription

let sharedSwiftSettings: [SwiftSetting] = [
    .unsafeFlags(["-Xfrontend", "-disable-availability-checking"]),
]

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
            name: "WizmacCore",
            swiftSettings: sharedSwiftSettings
        ),
        .target(
            name: "WizmacTextMode",
            dependencies: ["WizmacCore"],
            swiftSettings: sharedSwiftSettings
        ),
        .target(
            name: "WizmacSystem",
            dependencies: ["WizmacCore", "WizmacTextMode"],
            swiftSettings: sharedSwiftSettings
        ),
        .target(
            name: "WizmacControlPlane",
            dependencies: ["WizmacCore", "WizmacSystem"],
            swiftSettings: sharedSwiftSettings
        ),
        .executableTarget(
            name: "WizmacCLI",
            dependencies: ["WizmacCore", "WizmacSystem", "WizmacControlPlane"],
            swiftSettings: sharedSwiftSettings
        ),
        .executableTarget(
            name: "WizmacService",
            dependencies: ["WizmacCore", "WizmacSystem", "WizmacControlPlane"],
            swiftSettings: sharedSwiftSettings
        ),
        .executableTarget(
            name: "WizmacMenuBarApp",
            dependencies: ["WizmacCore", "WizmacSystem", "WizmacControlPlane"],
            swiftSettings: sharedSwiftSettings
        ),
        .target(
            name: "WizmacFixtureHostSupport",
            dependencies: [],
            path: "Sources/WizmacFixtureHostSupport",
            swiftSettings: sharedSwiftSettings
        ),
        .executableTarget(
            name: "WizmacFixtureHost",
            dependencies: [],
            path: "Sources/WizmacFixtureHost",
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "WizmacCoreTests",
            dependencies: ["WizmacCore"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "WizmacTextModeTests",
            dependencies: ["WizmacTextMode"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "WizmacSystemTests",
            dependencies: ["WizmacSystem"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "WizmacControlPlaneTests",
            dependencies: ["WizmacControlPlane"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "WizmacAppTests",
            dependencies: ["WizmacMenuBarApp", "WizmacFixtureHostSupport"],
            swiftSettings: sharedSwiftSettings
        ),
    ]
)
