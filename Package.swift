// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Twinee",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Twinee", targets: ["Twinee"]),
    ],
    targets: [
        .executableTarget(name: "Twinee"),
    ]
)
