// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Face2FaceCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "Face2FaceCore", targets: ["Face2FaceCore"])],
    targets: [
        .target(name: "Face2FaceCore"),
        .testTarget(name: "Face2FaceCoreTests", dependencies: ["Face2FaceCore"]),
    ]
)
