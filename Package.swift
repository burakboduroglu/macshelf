// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MacShelf",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacShelf", targets: ["MacShelf"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.4.0")
    ],
    targets: [
        .executableTarget(
            name: "MacShelf",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources/MacShelf",
            exclude: ["Resources/Info.plist", "Resources/MacShelf.entitlements"],
            resources: [
                .process("Resources/Assets.xcassets")
            ]
        )
    ]
)
