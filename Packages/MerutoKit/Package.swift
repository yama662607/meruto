// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MerutoKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MerutoCore", targets: ["MerutoCore"]),
        .library(name: "MerutoProbes", targets: ["MerutoProbes"]),
    ],
    targets: [
        // UI にも OS にも依存しない計算・モデル。アプリとウィジェットの両方から使う。
        .target(name: "MerutoCore"),
        // Darwin の低レベル API (mach / sysctl / getifaddrs / ICMP) で端末の値を読む。
        .target(name: "MerutoProbes", dependencies: ["MerutoCore"]),
        .testTarget(name: "MerutoCoreTests", dependencies: ["MerutoCore"]),
        .testTarget(name: "MerutoProbesTests", dependencies: ["MerutoProbes"]),
    ]
)
