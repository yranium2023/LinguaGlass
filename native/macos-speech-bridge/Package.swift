// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LinguaGlassSpeechBridge",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "LinguaGlassSpeechBridge", targets: ["LinguaGlassSpeechBridge"])],
    targets: [.executableTarget(name: "LinguaGlassSpeechBridge")]
)
