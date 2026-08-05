// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "multiterminal",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "multiterminal", targets: ["multiterminal"])
    ],
    dependencies: [
        // Miguel de Icaza's native Swift terminal emulator (AppKit + real PTY).
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.15.0")
    ],
    targets: [
        .executableTarget(
            name: "multiterminal",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/multiterminal"
        ),
        .testTarget(
            name: "multiterminalTests",
            dependencies: ["multiterminal"],
            path: "Tests/multiterminalTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
