// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "BeamMac",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "BeamMac", targets: ["BeamMac"])
  ],
  targets: [
    .executableTarget(
      name: "BeamMac",
      path: "Sources/BeamMac"
    )
  ]
)
