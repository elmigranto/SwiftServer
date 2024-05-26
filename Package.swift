// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "SwiftServer",

  platforms: [
    .macOS(.v14)
  ],

  dependencies: [
    .package(url: "https://github.com/apple/swift-nio.git", exact: "2.65.0"),
    .package(url: "https://github.com/vapor/postgres-nio.git", exact: "1.21.1")
  ],

  targets: [
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    .executableTarget(
      name: "SwiftServer",
      dependencies: [
        .product(name: "NIOHTTP1", package: "swift-nio"),
        .product(name: "PostgresNIO", package: "postgres-nio")
      ]
    )
  ]
)
