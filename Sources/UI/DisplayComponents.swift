// SPDX-License-Identifier: GPL-3.0-only
// MacHub — fork of HyperMac. Original work Copyright (C) 2026 Nguyễn Khắc Đại.
// Modifications Copyright (C) 2026 MacHub contributors.
// (Tách từ Views.swift của HyperMac.)

import SwiftUI

// MARK: - Display Card View

struct DisplayCardView: View {
    var monitor: DisplayInfo
    @ObservedObject var displayManager: DisplayManager
    var isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header Row
            HStack(spacing: 6) {
                Image(systemName: monitor.isBuiltIn ? "laptopcomputer" : "display")
                    .font(.system(size: FS.body))
                    .foregroundStyle(monitor.isConnected ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(monitor.name)
                        .font(.system(size: FS.label, weight: .semibold))
                        .lineLimit(1)
                    Text("\(monitor.resolution) • \(monitor.isBuiltIn ? tr("Màn hình chính", "Built-in Display") : tr("Màn hình ngoài", "External Display"))")
                        .font(.system(size: FS.caption))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(Int(round(monitor.brightness * 100)))%")
                    .font(.system(size: FS.body, weight: .semibold, design: .rounded))
                    .foregroundStyle(monitor.isConnected ? Color.primary : Color.secondary)
            }

            if monitor.isConnected {
                // Brightness Slider
                Slider(
                    value: Binding<Double>(
                        get: { monitor.brightness },
                        set: { displayManager.setBrightness($0, for: monitor) }
                    ),
                    in: 0...1
                )
                .controlSize(.small)

                DisplayModeControls(displayID: monitor.id, manager: .shared) {
                    // Disconnect toggle
                    Button {
                        displayManager.toggleConnection(for: monitor)
                    } label: {
                        Text(monitor.isBuiltIn ? tr("Tắt màn", "Turn Off") : tr("Ngắt mềm", "Disconnect"))
                            .font(.system(size: FS.caption, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(monitor.isBuiltIn && !displayManager.canDisconnect(monitor))
                }
            } else {
                HStack {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.orange.opacity(0.8))
                            .frame(width: 5, height: 5)
                        Text(tr("Đang ngắt mềm (Đã tắt)", "Disconnected (Turned Off)"))
                            .font(.system(size: FS.caption, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        displayManager.toggleConnection(for: monitor)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "power")
                                .font(.system(size: FS.caption, weight: .semibold))
                            Text(tr("Bật lại", "Turn On"))
                                .font(.system(size: FS.caption, weight: .semibold))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Rad.sm)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: Rad.sm)
                        .stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

// MARK: - Quick Actions Bar

struct QuickActionsBar: View {
    @ObservedObject var displayManager: DisplayManager

    var body: some View {
        HStack(spacing: 8) {
            if let ext = displayManager.monitors.first(where: { !$0.isBuiltIn }) {
                Button {
                    displayManager.toggleConnection(for: ext)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: ext.isConnected ? "display.slash" : "display")
                            .font(.system(size: FS.caption))
                        Text(ext.isConnected ? tr("Ngắt màn ngoài", "Disconnect External") : tr("Bật màn ngoài", "Connect External"))
                            .font(.system(size: FS.caption, weight: ext.isConnected ? .regular : .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color(nsColor: .controlBackgroundColor)))
                    .foregroundStyle(ext.isConnected ? Color.primary : Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if displayManager.monitors.contains(where: { !$0.isConnected }) {
                Button {
                    displayManager.connectAllDisplays()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: FS.caption))
                        Text(tr("Bật tất cả màn hình", "Turn On All Displays"))
                            .font(.system(size: FS.caption, weight: .semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "display.trianglebadge.exclamationmark")
                .font(.system(size: FS.display))
                .foregroundStyle(.tertiary)
            Text(tr("Không tìm thấy màn hình nào", "No displays detected"))
                .font(.system(size: FS.label))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}
