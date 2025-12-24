// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FileFlow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FileFlow", targets: ["FileFlow"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "FileFlow",
            dependencies: [],
            path: "FileFlow"
        )
    ]
)
