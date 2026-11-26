// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kawaru",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "kawaru", path: "Sources/kawaru"),
        // The camera extension; scripts/build.sh wraps it into a .systemextension inside the app.
        .executableTarget(name: "kawaru-camera", path: "Sources/kawaru-camera"),
    ]
)
