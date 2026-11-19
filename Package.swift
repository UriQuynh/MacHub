// swift-tools-version: 5.9
// SPDX-License-Identifier: GPL-3.0-only
// MacHub — fork of HyperMac. Original work Copyright (C) 2026 Nguyễn Khắc Đại.
// Modifications Copyright (C) 2026 MacHub contributors.
// Licensed under the GNU General Public License v3.0 (see LICENSE).
import PackageDescription

let package = Package(
    name: "MacHub",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Cập nhật tự động có chữ ký EdDSA (thay cho UpdateManager tự viết của HyperMac).
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .target(
            name: "VirtualDisplayBridge",
            path: "Sources/VirtualDisplayBridge",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "MacHub",
            dependencies: [
                "VirtualDisplayBridge",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources",
            exclude: ["VirtualDisplayBridge"],
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),
        .testTarget(name: "ScreenshotAnnotationTests", dependencies: ["MacHub"], path: "Tests/ScreenshotAnnotationTests"),
        .testTarget(name: "MacHubTests", dependencies: ["MacHub"], path: "Tests/MacHubTests")
    ]
)
