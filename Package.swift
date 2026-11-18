// swift-tools-version: 5.9
// SPDX-License-Identifier: GPL-3.0-only
// MacHub — fork of HyperMac. Original work Copyright (C) 2026 Nguyễn Khắc Đại.
// Modifications Copyright (C) 2026 MacHub contributors.
// Licensed under the GNU General Public License v3.0 (see LICENSE).
import PackageDescription

let package = Package(
    name: "MacHub",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "VirtualDisplayBridge",
            path: "Sources/VirtualDisplayBridge",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "MacHub",
            dependencies: ["VirtualDisplayBridge"],
            path: "Sources",
            exclude: ["VirtualDisplayBridge"],
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),
        .testTarget(name: "ScreenshotAnnotationTests", dependencies: ["MacHub"], path: "Tests/ScreenshotAnnotationTests")
    ]
)
