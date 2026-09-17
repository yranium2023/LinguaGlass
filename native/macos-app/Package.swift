// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LinguaGlassMac",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "LinguaGlassMac", targets: ["LinguaGlassMac"])
    ],
    targets: [
        .executableTarget(name: "LinguaGlassMac")
    ]
)
