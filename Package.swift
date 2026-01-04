// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "XcodeAIStand",
  platforms: [
    .macOS(.v13)
  ],
  dependencies: [],
  targets: [
    .executableTarget(
      name: "XcodeAIStand",
      dependencies: []
    )
  ]
)
