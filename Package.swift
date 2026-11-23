// swift-tools-version: 6.2
import PackageDescription

let fluid = Target.Dependency.product(name: "FluidAudio", package: "FluidAudio")
let sparkle = Target.Dependency.product(name: "Sparkle", package: "Sparkle")

let package = Package(
    name: "Spitball",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.4"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
    ],
    targets: [
        .target(name: "ObjCCatch", path: "Sources/ObjCCatch"),
        .executableTarget(name: "Spitball", dependencies: [fluid, sparkle, "ObjCCatch"], path: "Sources/Spitball",
                          swiftSettings: [.swiftLanguageMode(.v6), .defaultIsolation(MainActor.self)]),
    ]
)
