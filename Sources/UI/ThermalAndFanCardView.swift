// SPDX-License-Identifier: GPL-3.0-only
// MacHub — fork of HyperMac. Original work Copyright (C) 2026 Nguyễn Khắc Đại.
// Modifications Copyright (C) 2026 MacHub contributors.
// (Tách từ Views.swift của HyperMac.)

import SwiftUI

// MARK: - Thermal & Fan Control View (Macs Fan Control + Apple Silicon Thermal Suite)

/* Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V5 */
struct ThermalAndFanCardView: View {
    @ObservedObject var thermalManager: ThermalManager
    @ObservedObject var systemMonitor: SystemMonitorManager

    var body: some View {
        VStack(spacing: 8) {
            // 1. Device Profile & Thermal Health Header
            deviceHeaderCard

            // 1b. Fan control (hidden on fanless Macs)
            FanControlCardView(fan: FanManager.shared)

            // 2. Optional Menu Bar temperature pill
            menuBarMonitorRow

            // 3. Apple Silicon 6-Sensor Telemetry Matrix
            thermalMatrixGrid

            // 4. Detailed Sensor Breakdown (Expandable Accordion)
            detailedSensorsAccordion
        }
    }

    // MARK: - 1. Device Header Card
    private var deviceHeaderCard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(headerIconBackground)
                        .frame(width: 32, height: 32)

                    Image(systemName: "thermometer.medium")
                        .font(.system(size: FS.subhead, weight: .semibold))
                        .foregroundStyle(headerIconColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(thermalManager.machineModelName)
                            .font(.system(size: FS.body, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("SMC + HID")
                            .font(.system(size: FS.caption, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                            .foregroundStyle(.secondary)
                    }

                    Text(tr("Cảm biến nhiệt Apple Silicon • Cập nhật mỗi 2.5s", "Apple Silicon Thermal Sensors • Updates every 2.5s"))
                        .font(.system(size: FS.caption))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Thermal State Pill
                HStack(spacing: 3) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 5, height: 5)
                    Text(localizedThermalStateDescription)
                        .font(.system(size: FS.caption, weight: .semibold))
                        .foregroundStyle(stateColor)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(stateColor.opacity(0.12)))

                // Refresh Button
                Button {
                    thermalManager.isRefreshing = true
                    thermalManager.refreshMetrics()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        thermalManager.isRefreshing = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: FS.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(thermalManager.isRefreshing ? 360 : 0))
                        .animation(thermalManager.isRefreshing ? .linear(duration: 0.4) : .default, value: thermalManager.isRefreshing)
                        .padding(5)
                        .background(Circle().fill(Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .help(tr("Làm mới cảm biến nhiệt ngay lập tức", "Refresh thermal sensors immediately"))
            }
        }
        .padding(8)
        .cardBackground()
    }

    // MARK: - 2. Menu Bar Monitor (Temperature, CPU/RAM, Separate GPU Option)

    /* Hallmark · component: menubar-metrics-card · genre: macos-native · theme: system-tokens · pre-emit critique: P5 H5 E5 S5 R5 V4 */
    private var menuBarMonitorRow: some View {
        VStack(spacing: 6) {
            menuBarToggleRow(
                icon: "menubar.dock.rectangle",
                title: tr("Hiện nhiệt độ trên Menu Bar", "Show temperature on Menu Bar"),
                preview: thermalManager.showMenuBarMetrics ? "\(Int(thermalManager.displayTemp.rounded()))°C" : nil,
                isOn: Binding<Bool>(
                    get: { thermalManager.showMenuBarMetrics },
                    set: { thermalManager.showMenuBarMetrics = $0 }
                )
            )

            Divider().opacity(0.45)

            menuBarToggleRow(
                icon: "cpu",
                title: tr("Hiện % CPU & RAM trên Menu Bar", "Show CPU & RAM % on Menu Bar"),
                preview: systemMonitor.showCPURAMMenuBar
                    ? "CPU \(Int(systemMonitor.cpuUsagePercent.rounded()))% · RAM \(Int(systemMonitor.ramUsagePercent.rounded()))%"
                    : nil,
                isOn: Binding<Bool>(
                    get: { systemMonitor.showCPURAMMenuBar },
                    set: { systemMonitor.showCPURAMMenuBar = $0 }
                ),
                tooltip: tr("Hiển thị % CPU và % RAM đang sử dụng lên thanh Menu Bar",
                            "Display active CPU and RAM usage percentage on the Menu Bar")
            )

            Divider().opacity(0.45)

            menuBarToggleRow(
                icon: "square.3.layers.3d",
                title: tr("Hiện % GPU trên Menu Bar (riêng)", "Show GPU % on Menu Bar (separate)"),
                preview: !systemMonitor.hasGPU
                    ? tr("Không hỗ trợ", "Unsupported")
                    : (systemMonitor.showGPUMenuBar ? "GPU \(Int(systemMonitor.gpuUsagePercent.rounded()))%" : nil),
                isOn: Binding<Bool>(
                    get: { systemMonitor.showGPUMenuBar && systemMonitor.hasGPU },
                    set: { systemMonitor.showGPUMenuBar = $0 }
                ),
                isDisabled: !systemMonitor.hasGPU,
                isMutedPreview: !systemMonitor.hasGPU,
                tooltip: tr("Tùy chọn riêng để hiển thị % sử dụng GPU (nếu có) lên thanh Menu Bar",
                            "Separate option to display GPU utilization percentage (if available) on the Menu Bar")
            )
        }
        .padding(8)
        .cardBackground()
    }

    private func menuBarToggleRow(
        icon: String,
        title: String,
        preview: String?,
        isOn: Binding<Bool>,
        isDisabled: Bool = false,
        isMutedPreview: Bool = false,
        tooltip: String? = nil
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: FS.caption))
                .foregroundStyle(isDisabled ? Tone.muted : Color.accentColor)
                .frame(width: 14)

            Text(title)
                .font(.system(size: FS.caption))
                .foregroundStyle(isDisabled ? .tertiary : .secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let preview {
                Text(preview)
                    .font(.system(size: FS.caption, weight: isMutedPreview ? .regular : .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isMutedPreview ? Color.secondary.opacity(0.6) : Color.accentColor)
                    .lineLimit(1)
            }

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(isDisabled)
        }
        .help(tooltip ?? "")
    }

    // MARK: - 3. Apple Silicon Thermal Matrix (6 Core Metrics)
    private var thermalMatrixGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(tr("Bản đồ nhiệt Apple Silicon (SMC + HID)", "Apple Silicon Thermal Matrix (SMC + HID)"), systemImage: "cpu")
                    .font(.system(size: FS.caption, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text(tr("Thời gian thực: 2.5s", "Real-time: 2.5s"))
                    .font(.system(size: FS.caption))
                    .foregroundStyle(.tertiary)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 5) {
                sensorTile(
                    title: tr("CPU Trung bình", "CPU Average"),
                    temp: thermalManager.cpuAvgTemp,
                    icon: "cpu",
                    sub: tr("Tất cả các nhân", "All Cores Average")
                )
                sensorTile(
                    title: tr("CPU Nóng nhất", "CPU Peak"),
                    temp: thermalManager.cpuPeakTemp,
                    icon: "flame.fill",
                    sub: "Core Peak Hotspot"
                )
                sensorTile(
                    title: tr("GPU Đồ họa", "GPU Core"),
                    temp: thermalManager.gpuAvgTemp,
                    icon: "gamecontroller.fill",
                    sub: tr("Cụm nhân GPU", "GPU Cluster")
                )
                sensorTile(
                    title: tr("Pin Cell", "Battery Pack"),
                    temp: thermalManager.batteryTemp,
                    icon: "battery.100.bolt",
                    sub: "Gas Gauge Pack"
                )
                sensorTile(
                    title: tr("Ổ cứng SSD", "SSD Storage"),
                    temp: thermalManager.ssdTemp,
                    icon: "internaldrive.fill",
                    sub: "NAND Flash Storage"
                )
                sensorTile(
                    title: tr("Hotspot Bo mạch", "Motherboard Hotspot"),
                    temp: thermalManager.hotspotTemp,
                    icon: "thermometer.sun.fill",
                    sub: "PMU Calibration"
                )
            }
        }
        .padding(8)
        .cardBackground()
    }

    private func sensorTile(title: String, temp: Double, icon: String, sub: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: FS.body))
                .foregroundStyle(tempColor(temp))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: FS.caption, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(temp > 0 ? String(format: "%.1f°C", temp) : "—")
                    .font(.system(size: FS.body, weight: .semibold, design: .rounded))
                    .foregroundStyle(tempColor(temp))

                Text(sub)
                    .font(.system(size: FS.caption))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4.5)
        .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.03)))
    }

    // MARK: - 4. Detailed Sensor Breakdown Accordion
    private var detailedSensorsAccordion: some View {
        VStack(spacing: 4) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    thermalManager.isDetailExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: FS.caption))
                        .foregroundStyle(Color.accentColor)

                    Text(tr("Chi tiết \(thermalManager.detailedSensors.count) cảm biến trên chip", "Detailed \(thermalManager.detailedSensors.count) on-chip sensors"))
                        .font(.system(size: FS.caption, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: thermalManager.isDetailExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: FS.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4.5)
                .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.04)))
            }
            .buttonStyle(.plain)

            if thermalManager.isDetailExpanded {
                VStack(spacing: 3) {
                    ForEach(thermalManager.detailedSensors) { s in
                        HStack {
                            Text(s.displayName)
                                .font(.system(size: FS.caption, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("(\(s.name))")
                                .font(.system(size: FS.caption))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text(String(format: "%.1f°C", s.temp))
                                .font(.system(size: FS.caption, weight: .semibold, design: .rounded))
                                .foregroundStyle(tempColor(s.temp))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.02)))
            }
        }
    }

    private func tempColor(_ temp: Double) -> Color {
        guard temp > 0 else { return .secondary }
        if temp < 55.0 {
            return Tone.good
        } else if temp < 75.0 {
            return .orange
        } else {
            return .red
        }
    }

    private var stateColor: Color {
        if thermalManager.isThrottling {
            return .red
        }
        switch thermalManager.thermalLevel {
        case .cool: return Tone.good
        case .warm: return .orange
        case .hot:  return .red
        }
    }

    private var localizedThermalStateDescription: String {
        // thermalState chỉ báo áp lực nhiệt (giảm xung), vẫn "nominal" ở 9x°C — nên khi chưa giảm xung thì mô tả theo CPU trung bình, cùng ngưỡng với stateColor.
        switch ProcessInfo.processInfo.thermalState {
        case .nominal, .fair:
            switch thermalManager.thermalLevel {
            case .cool: return tr("Mát mẻ (Bình thường)", "Cool (Normal)")
            case .warm: return tr("Ấm (Tải vừa)", "Warm (Moderate)")
            case .hot:  return tr("Nóng (Chưa giảm xung)", "Hot (Not throttling)")
            }
        case .serious: return tr("Nóng (Đang giảm xung)", "Serious (Throttling)")
        case .critical: return tr("Rất nóng (Throttling tối đa!)", "Critical (Heavy Throttling!)")
        @unknown default: return tr("Bình thường", "Normal")
        }
    }

    private var headerIconColor: Color {
        Color.accentColor
    }

    private var headerIconBackground: Color {
        Color.accentColor.opacity(0.12)
    }
}
