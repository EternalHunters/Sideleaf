// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlomoMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FlomoMac", targets: ["FlomoMac"])
    ],
    targets: [
        .executableTarget(
            name: "FlomoMac",
            path: "Sources/FlomoMac",
            exclude: ["Resources"]
        )
    ],
    swiftLanguageModes: [.v5]
)
