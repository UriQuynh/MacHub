// SPDX-License-Identifier: GPL-3.0-only
// MacHub — fork of HyperMac. Original work Copyright (C) 2026 Nguyễn Khắc Đại.
// Modifications Copyright (C) 2026 MacHub contributors.
// (Tách từ Views.swift của HyperMac.)

import SwiftUI

// MARK: - Footer

/* Hallmark · component: footer-license-pill · genre: macos-native · theme: system-tokens · pre-emit critique: P5 H5 E5 S5 R5 V4 */
struct FooterView: View {
    @ObservedObject var updateManager: UpdateManager

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: FS.caption))
                    .foregroundStyle(.secondary)
                Text(tr("GPLv3 • Miễn phí", "GPLv3 • Free"))
                    .font(.system(size: FS.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .help(tr("MacHub — dựa trên HyperMac © 2026 Nguyễn Khắc Đại • GNU GPLv3", "MacHub — based on HyperMac © 2026 Nguyen Khac Dai • GNU GPLv3"))

            Spacer()

            // Author Link Button
            Button {
                if let url = URL(string: "https://github.com/mrgoose000000-gif/HyperMac") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: FS.caption))
                    Text(tr("Dự án gốc", "Original"))
                        .font(.system(size: FS.caption, weight: .medium))
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(
                    Capsule().fill(Color.primary.opacity(0.06))
                )
                .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .help(tr("MacHub được phát triển từ HyperMac của Nguyễn Khắc Đại", "MacHub is based on HyperMac by Nguyen Khac Dai"))

            // Update Check / Action Button
            if !UpdateManager.updatesDisabled {
                Button {
                    updateManager.checkForUpdates(silent: false)
                } label: {
                    HStack(spacing: 3.5) {
                        Image(systemName: updateManager.hasNewUpdate ? "sparkles" : "arrow.triangle.2.circlepath")
                            .font(.system(size: FS.caption))
                        let cleanVer = updateManager.latestVersionString.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                        Text(updateManager.hasNewUpdate ? tr("Có bản v\(cleanVer)", "New v\(cleanVer)") : tr("Cập nhật", "Updates"))
                            .font(.system(size: FS.caption, weight: updateManager.hasNewUpdate ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule().fill(updateManager.hasNewUpdate ? Tone.good.opacity(0.12) : Color.primary.opacity(0.06))
                    )
                    .foregroundStyle(updateManager.hasNewUpdate ? Tone.good : Color.primary)
                }
                .buttonStyle(.plain)
                .help(updateManager.hasNewUpdate ? tr("Đã có bản mới! Bấm để cập nhật", "New version available! Click to update") : tr("Kiểm tra phiên bản mới từ GitHub", "Check for newer version on GitHub"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }
}
