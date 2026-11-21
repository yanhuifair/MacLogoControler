// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MacLogoControl",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacLogoControl", targets: ["MacLogoControl"]),
    ],
    targets: [
        // Hardware access and privileged commands. No UI code lives here.
        .target(
            name: "MacLogoControlCore",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // The menu bar app.
        .executableTarget(
            name: "MacLogoControl",
            dependencies: ["MacLogoControlCore"]
        ),
        // Self-contained test runner (`swift run MacLogoControlTests`).
        // XCTest and swift-testing are only available with a full Xcode install,
        // so this keeps the project buildable and testable with the Command Line Tools alone.
        .executableTarget(
            name: "MacLogoControlTests",
            dependencies: ["MacLogoControlCore"]
        ),
    ]
)
