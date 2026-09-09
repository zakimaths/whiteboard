// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Whiteboard",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Whiteboard", targets: ["WhiteboardApp"])],
    targets: [
        .target(name: "WhiteboardCore", resources: [.copy("Resources/PDE")]),
        .executableTarget(name: "WhiteboardApp", dependencies: ["WhiteboardCore"]),
        .executableTarget(name: "WhiteboardPDEAssets", dependencies: ["WhiteboardCore"], path: "Tools/PDEAssets"),
        .executableTarget(name: "WhiteboardSamples", dependencies: ["WhiteboardCore"], path: "Tools/Samples"),
        .executableTarget(name: "WhiteboardChecks", dependencies: ["WhiteboardCore"], path: "Tests/WhiteboardCoreTests")
    ]
)
