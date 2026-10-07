// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AltrStreamApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Altr Stream", targets: ["AltrStreamApp"])
    ],
    targets: [
        .executableTarget(
            name: "AltrStreamApp",
            path: "Sources"
        )
    ]
)
