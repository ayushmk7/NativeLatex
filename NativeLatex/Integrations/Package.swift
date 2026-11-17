// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NativeLatexIntegrations",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NativeLatexIntegrations", targets: ["NativeLatexIntegrations"]),
    ],
    targets: [
        .target(name: "NativeLatexIntegrations"),
        // Fixtures are read from docs/research/conversion-fixtures so the
        // documented conversion test and these tests share one corpus.
        .testTarget(name: "NativeLatexIntegrationsTests", dependencies: ["NativeLatexIntegrations"]),
    ]
)
