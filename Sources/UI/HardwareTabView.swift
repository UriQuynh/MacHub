// SPDX-License-Identifier: GPL-3.0-only
// MacHub — fork of HyperMac. Original work Copyright (C) 2026 Nguyễn Khắc Đại.
// Modifications Copyright (C) 2026 MacHub contributors.
// (Tách từ Views.swift của HyperMac.)

import SwiftUI

// MARK: - TAB 0: Hardware Care, Battery & Thermal View

struct HardwareCareTabView: View {
    @ObservedObject var batteryManager: BatteryManager
    @ObservedObject var thermalManager: ThermalManager = ThermalManager.shared
    @ObservedObject var systemMonitor: SystemMonitorManager = SystemMonitorManager.shared

    var body: some View {
        VStack(spacing: 6) {
            // Segment Switcher: Pin & Nguồn vs Tản nhiệt & Quạt
            HStack(spacing: 4) {
                sectionButton(
                    index: 0,
                    title: tr("Pin & Nguồn SMC", "Battery & Power SMC"),
                    icon: "bolt.shield.fill"
                )
                sectionButton(
                    index: 1,
                    title: tr("Nhiệt độ & Cảm biến", "Thermals & Sensors"),
                    icon: "thermometer.sun.fill",
                    badge: thermalManager.cpuAvgTemp > 0 ? String(format: "%.0f°C", thermalManager.displayTemp) : nil
                )
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.04)))
            .padding(.horizontal, 12)
            .padding(.top, 4)

            // Tốc độ truyền file (ổ vật lý + LAN/NAS) — luôn hiển thị
            FileTransferSpeedCard()
                .padding(.horizontal, 12)
                .padding(.top, 4)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    if thermalManager.selectedSection == 0 {
                        BatteryCardView(batteryManager: batteryManager, onSelectThermalSection: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                thermalManager.selectedSection = 1
                            }
                        })
                    } else {
                        ThermalAndFanCardView(thermalManager: thermalManager, systemMonitor: systemMonitor)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
    }

    private func sectionButton(index: Int, title: String, icon: String, badge: String? = nil) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                thermalManager.selectedSection = index
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: FS.caption, weight: thermalManager.selectedSection == index ? .semibold : .medium))

                if let badge = badge, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: FS.caption, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(thermalManager.selectedSection == index ? Color.white.opacity(0.25) : Color.primary.opacity(0.08)))
                }
            }
            .padding(.vertical, 4.5)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: Rad.sm))
            .background(
                RoundedRectangle(cornerRadius: Rad.sm)
                    .fill(thermalManager.selectedSection == index ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(thermalManager.selectedSection == index ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - File Transfer Speed Card (ổ vật lý + LAN/NAS)

/* Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V5 */
struct FileTransferSpeedCard: View {
    @ObservedObject var diskSpeed: DiskSpeedManager = DiskSpeedManager.shared

    private var isActive: Bool {
        diskSpeed.totalReadMBps >= 0.05 || diskSpeed.totalWriteMBps >= 0.05 ||
        diskSpeed.networkReadMBps >= 0.05 || diskSpeed.networkWriteMBps >= 0.05
    }

    private var busiestDisk: DiskSpeedInfo? {
        diskSpeed.disks.filter(\.isActive).max { $0.totalMBps < $1.totalMBps }
    }

    /// Nguồn → đích của phiên chép đang chạy (ví dụ "U280-Pro → SSD nội bộ").
    /// Khi chỉ có một ổ vừa đọc vừa ghi thì hiện tên ổ đó.
    private var transferPath: String? {
        let reader = diskSpeed.disks
            .filter { $0.readMBps >= 1 }
            .max { $0.readMBps < $1.readMBps }
        let writer = diskSpeed.disks
            .filter { $0.writeMBps >= 1 }
            .max { $0.writeMBps < $1.writeMBps }

        switch (reader, writer) {
        case let (source?, destination?) where source.bsdName != destination.bsdName:
            return "\(source.displayName) → \(destination.displayName)"
        case let (_, destination?):
            return destination.displayName
        case let (source?, nil):
            return "\(tr("Đọc từ", "Reading from")) \(source.displayName)"
        default:
            return busiestDisk?.displayName
        }
    }

    private var networkActive: Bool {
        diskSpeed.networkReadMBps >= 0.05 || diskSpeed.networkWriteMBps >= 0.05
    }

    private var detailText: String? {
        var parts: [String] = []
        if let path = transferPath {
            parts.append(path)
        }
        if networkActive, let label = diskSpeed.networkLabel {
            parts.append("\(label) (NAS)")
        }
        if let process = diskSpeed.topProcessName {
            parts.append("\(process) \(speedText(max(diskSpeed.topProcessWriteMBps, diskSpeed.topProcessReadMBps)))")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private var tooltip: String {
        var lines = [tr("Tổng hợp mọi ổ vật lý đang đọc/ghi", "Aggregated active physical drives read/write")]
        for disk in diskSpeed.disks where disk.isActive {
            lines.append("\(disk.displayName): ↓\(speedText(disk.readMBps)) ↑\(speedText(disk.writeMBps))")
        }
        if let label = diskSpeed.networkLabel {
            lines.append("\(label): ↓\(speedText(diskSpeed.networkReadMBps)) ↑\(speedText(diskSpeed.networkWriteMBps))")
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .font(.system(size: FS.caption))
                    .foregroundStyle(diskSpeed.isEnabled && isActive ? Color.accentColor : Color.secondary)

                Text(diskSpeed.isEnabled ? tr("Chép file", "File Transfer") : tr("Đo tốc độ chép file", "Transfer Speed"))
                    .font(.system(size: FS.caption, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer()

                if diskSpeed.isEnabled {
                    speedChip(icon: "arrow.down", value: diskSpeed.totalReadMBps, color: .accentColor)
                    speedChip(icon: "arrow.up", value: diskSpeed.totalWriteMBps, color: .secondary)

                    if diskSpeed.networkLabel != nil {
                        Divider().frame(height: 9)
                        speedChip(icon: "network", value: max(diskSpeed.networkReadMBps, diskSpeed.networkWriteMBps), color: .secondary)
                    }
                }

                Toggle("", isOn: Binding(
                    get: { diskSpeed.isEnabled },
                    set: { diskSpeed.setEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help(diskSpeed.isEnabled
                      ? "Đang đo khi bảng này mở. Tắt để MacHub ngừng quét hoàn toàn."
                      : "Bật để đo tốc độ chép file (ổ cứng, thẻ nhớ, NAS qua LAN).")
            }

            if diskSpeed.isEnabled, let detail = detailText {
                Text(detail)
                    .font(.system(size: FS.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .cardBackground()
        .help(diskSpeed.isEnabled ? tooltip : "Đo tốc độ chép file đang tắt")
        .animation(.easeOut(duration: 0.2), value: detailText)
    }

    private func speedChip(icon: String, value: Double, color: Color) -> some View {
        let active = value >= 0.05
        return HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: FS.caption, weight: .semibold))
            Text(Self.speedText(value))
                .font(.system(size: FS.caption, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(active ? color : Color.secondary.opacity(0.7))
    }

    static func speedText(_ mbps: Double) -> String {
        if mbps >= 1024 { return String(format: "%.1f GB/s", mbps / 1024) }
        if mbps >= 10 { return String(format: "%.0f MB/s", mbps) }
        if mbps >= 0.1 { return String(format: "%.1f MB/s", mbps) }
        if mbps >= 0.01 { return String(format: "%.0f KB/s", mbps * 1024) }
        return "0 MB/s"
    }

    private func speedText(_ mbps: Double) -> String { Self.speedText(mbps) }
}
