// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "DeferredFinishCore",
    platforms: [.macOS(.v10_15), .iOS(.v15)],
    products: [.library(name: "DeferredFinishCore", targets: ["DeferredFinishCore"])],
    targets: [
        .target(name: "DeferredFinishCore", path: "godot_plugin", sources: ["DeferredFinishCoordinator.swift"]),
        .testTarget(name: "DeferredFinishCoreTests", dependencies: ["DeferredFinishCore"], path: "Tests"),
    ]
)
