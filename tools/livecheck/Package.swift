// swift-tools-version:6.0
import PackageDescription
let package = Package(name: "MacLogoControlLiveTest", platforms: [.macOS(.v14)],
  targets: [
    .target(name: "MacLogoControlCore", linkerSettings: [.linkedFramework("IOKit")]),
    .executableTarget(name: "MacLogoControlLiveTest", dependencies: ["MacLogoControlCore"])])
