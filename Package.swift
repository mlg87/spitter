// swift-tools-version: 6.0
import PackageDescription

// macOS 13 floor: SFSpeechRecognizer.addsPunctuation and SMAppService (launch at login)
// both require Ventura.
let package = Package(
    name: "spitter",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SpitterCore"),
        .executableTarget(name: "Spitter", dependencies: ["SpitterCore"]),
        .executableTarget(name: "SpitterTests", dependencies: ["SpitterCore"]),
    ]
)
