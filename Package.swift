// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SmartDPI",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "SmartDPI", targets: ["SmartDPI"])],
    targets: [
        .target(name: "SmartDPICore"),
        .target(name: "VirtualDisplayBridge", publicHeadersPath: "include",
                cSettings: [.unsafeFlags(["-fobjc-arc"])],
                linkerSettings: [.linkedFramework("Foundation"), .linkedFramework("CoreGraphics")]),
        .executableTarget(name: "SmartDPI", dependencies: ["SmartDPICore", "VirtualDisplayBridge"],
                          linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("CoreGraphics")]),
        .testTarget(name: "SmartDPICoreTests", dependencies: ["SmartDPICore"]),
        .testTarget(name: "SmartDPIStoreTests", dependencies: ["SmartDPI", "SmartDPICore"])
    ]
)
