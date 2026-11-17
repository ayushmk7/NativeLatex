// swift-tools-version: 6.0
import PackageDescription

// Write-view rendering of Markdown tables, local images and TeX math. A package so its tests run hostless
// (`swift test`): no app launch, no window on screen.
let package = Package(
    name: "NativeLatexMarkdownObjects",
    platforms: [.macOS(.v14)],
    products: [.library(name: "NativeLatexMarkdownObjects", targets: ["NativeLatexMarkdownObjects"])],
    targets: [
        .target(name: "NativeLatexMarkdownObjects", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "NativeLatexMarkdownObjectsTests", dependencies: ["NativeLatexMarkdownObjects"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
