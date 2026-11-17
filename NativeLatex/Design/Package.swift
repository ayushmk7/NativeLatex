// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NativeLatexDesign",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NativeLatexDesign", targets: ["NativeLatexDesign"]),
    ],
    targets: [
        .target(name: "NativeLatexDesign"),
        // Sample window + screenshot renderer: `swift run NativeLatexDesignDemo [--snapshot dir]`
        .executableTarget(name: "NativeLatexDesignDemo", dependencies: ["NativeLatexDesign"]),
        .testTarget(name: "NativeLatexDesignTests", dependencies: ["NativeLatexDesign"]),
    ]
)
