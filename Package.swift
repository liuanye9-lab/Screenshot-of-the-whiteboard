// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SnapLeaf",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SnapLeaf",
            path: "Sources",
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Vision"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
            ]
        )
    ]
)
