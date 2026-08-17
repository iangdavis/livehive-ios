// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LiveHive",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "LiveHive", targets: ["LiveHive"]),
    ],
    targets: [
        .target(name: "LiveHive"),
        .testTarget(
            name: "LiveHiveTests",
            dependencies: ["LiveHive"]
        ),
    ]
)
