// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MIR4DPatentSourceListing",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MIR4DPatentSourceListing", targets: ["MIR4DPatentSourceListing"])
    ],
    targets: [
        .executableTarget(
            name: "MIR4DPatentSourceListing",
            path: "Sources/MIR4DPatentSourceListing"
        ),
        .testTarget(
            name: "MIR4DPatentSourceListingTests",
            dependencies: ["MIR4DPatentSourceListing"],
            path: "Tests/MIR4DPatentSourceListingTests"
        )
    ]
)
