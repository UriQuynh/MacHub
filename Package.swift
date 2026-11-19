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
        // Lõi theo dõi agent (Claude Code, Codex): chỉ Foundation, dùng chung cho app và hook.
        .target(
            name: "AgentKit",
            path: "Sources/AgentKit"
        ),
        // Chương trình nhỏ Claude Code gọi qua hook/statusLine; build.sh nhúng vào MacHub.app.
        .executableTarget(
            name: "machub-agent-hook",
            dependencies: ["AgentKit"],
            path: "Sources/AgentHook"
        ),
        .executableTarget(
            name: "MacHub",
            dependencies: [
                "VirtualDisplayBridge",
                "AgentKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources",
            exclude: ["VirtualDisplayBridge", "AgentKit", "AgentHook"],
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),
        .testTarget(name: "ScreenshotAnnotationTests", dependencies: ["MacHub"], path: "Tests/ScreenshotAnnotationTests"),
        .testTarget(name: "MacHubTests", dependencies: ["MacHub"], path: "Tests/MacHubTests"),
        .testTarget(name: "AgentKitTests", dependencies: ["AgentKit", "machub-agent-hook"], path: "Tests/AgentKitTests")
    ]
)
