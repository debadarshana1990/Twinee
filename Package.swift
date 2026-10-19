// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Twinee",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Twinee", targets: ["Twinee"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(name: "Twinee", dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")]),
    ]
)
