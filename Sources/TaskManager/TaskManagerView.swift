// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import SwiftUI
import AppKit

// MARK: - Cửa sổ chính

struct TaskManagerView: View {
    @ObservedObject var model: TaskManagerModel
    @ObservedObject private var language = LanguageManager.shared
    @State private var pending: PendingAction?

    struct PendingAction: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let confirmLabel: String
        let run: () -> Void
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            Group {
                switch model.section {
                case .processes: ProcessesPane(model: model, confirm: confirm)
                case .performance: PerformancePane(model: model)
                case .details: DetailsPane(model: model, confirm: confirm)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            statusBar
        }
        .frame(minWidth: 760, minHeight: 480)
        .id(language.currentLanguage)
        .alert(item: $pending) { action in
            Alert(title: Text(action.title), message: Text(action.detail),
                  primaryButton: .destructive(Text(action.confirmLabel), action: action.run),
                  secondaryButton: .cancel(Text(tr("Hủy", "Cancel"))))
        }
    }

    private func confirm(title: String, detail: String, label: String, run: @escaping () -> Void) {
        pending = PendingAction(title: title, detail: detail, confirmLabel: label, run: run)
    }

    // MARK: Thanh công cụ

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $model.section) {
                Text(tr("Tiến trình", "Processes")).tag(TaskManagerModel.Section.processes)
                Text(tr("Hiệu năng", "Performance")).tag(TaskManagerModel.Section.performance)
                Text(tr("Chi tiết", "Details")).tag(TaskManagerModel.Section.details)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300)

            Spacer()

            if model.section != .performance {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(tr("Tìm theo tên, PID, đường dẫn", "Search name, PID, path"), text: $model.search)
                        .textFieldStyle(.plain)
                        .frame(width: 200)
                    if !model.search.isEmpty {
                        Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.06)))

                Button(role: .destructive) { endSelected(force: false) } label: {
                    Label(tr("Kết thúc tác vụ", "End task"), systemImage: "xmark.circle")
                }
                .disabled(model.selectedRows().isEmpty)
                .keyboardShortcut(.delete, modifiers: [])
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func endSelected(force: Bool) {
        let targets = model.selectedRows()
        guard !targets.isEmpty else { return }
        let name = targets.count == 1 ? targets[0].name : (model.groups.first { $0.id == model.selectedGroupID }?.name ?? targets[0].name)
        confirm(
            title: force ? tr("Buộc dừng \(name)?", "Force quit \(name)?") : tr("Kết thúc \(name)?", "End \(name)?"),
            detail: force
                ? tr("Tiến trình bị dừng ngay, dữ liệu chưa lưu sẽ mất.", "The process stops immediately; unsaved data is lost.")
                : tr("\(targets.count) tiến trình sẽ nhận yêu cầu thoát. Dữ liệu chưa lưu có thể mất.", "\(targets.count) process(es) will be asked to quit. Unsaved data may be lost."),
            label: force ? tr("Buộc dừng", "Force quit") : tr("Kết thúc", "End")
        ) { force ? model.forceKill(targets) : model.endTask(targets) }
    }

    // MARK: Thanh trạng thái

    private var statusBar: some View {
        HStack(spacing: 14) {
            Text(tr("\(model.system.processCount) tiến trình", "\(model.system.processCount) processes"))
            Text(tr("\(model.system.threadCount) luồng", "\(model.system.threadCount) threads"))
            Text(tr("CPU ", "CPU ") + TaskManagerFormat.percent(model.system.cpuPercent))
            Text(tr("Bộ nhớ ", "Memory ") + TaskManagerFormat.percent(model.system.memoryPercent))
            Spacer()
            if let message = model.message {
                Text(message).foregroundStyle(Tone.warn).lineLimit(1)
                Button { model.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
        }
        .font(.system(size: FS.label))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 5)
    }
}

// MARK: - Cột và ô số

private enum Col {
    static let num: CGFloat = 84
    static let pid: CGFloat = 64
    static let wide: CGFloat = 110
}

/// Màu nền ô theo mức dùng (vàng → cam → đỏ), giống cách Task Manager tô nóng/lạnh.
private func heat(_ fraction: Double) -> Color {
    let f = min(max(fraction, 0), 1)
    guard f > 0.01 else { return .clear }
    return (f > 0.6 ? Color.red : (f > 0.25 ? Color.orange : Color.yellow)).opacity(0.10 + 0.30 * f)
}

private struct HeaderCell: View {
    let title: String
    let key: ProcessSortKey
    @ObservedObject var model: TaskManagerModel
    var summary: String?
    var width: CGFloat?
    var alignment: Alignment = .trailing

    var body: some View {
        Button { model.toggleSort(key) } label: {
            VStack(alignment: alignment == .leading ? .leading : .trailing, spacing: 1) {
                if let summary { Text(summary).font(.system(size: FS.label, weight: .semibold)).foregroundStyle(Tone.accent) }
                HStack(spacing: 2) {
                    Text(title).font(.system(size: FS.label, weight: .medium))
                    if model.sortKey == key {
                        Image(systemName: model.sortAscending ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold))
                    }
                }
            }
            .frame(maxWidth: width == nil ? .infinity : width, alignment: alignment)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .frame(width: width)
    }
}

private struct NumCell: View {
    let text: String
    let fraction: Double
    var width: CGFloat = Col.num
    var body: some View {
        Text(text)
            .font(.system(size: FS.body).monospacedDigit())
            .frame(width: width, alignment: .trailing)
            .padding(.vertical, 4).padding(.horizontal, 6)
            .background(heat(fraction))
            .frame(width: width + 12)
    }
}

@MainActor
private final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]
    func icon(forApp path: String?) -> NSImage {
        let key = path ?? "_exec"
        if let hit = cache[key] { return hit }
        let image: NSImage
        if let path { image = NSWorkspace.shared.icon(forFile: path) }
        else { image = NSWorkspace.shared.icon(for: .unixExecutable) }
        image.size = NSSize(width: 16, height: 16)
        cache[key] = image
        return image
    }
}

// MARK: - Tab Tiến trình

private struct ProcessesPane: View {
    @ObservedObject var model: TaskManagerModel
    let confirm: (_ title: String, _ detail: String, _ label: String, _ run: @escaping () -> Void) -> Void

    var body: some View {
        let sections = model.visibleGroups
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HeaderCell(title: tr("Tên", "Name"), key: .name, model: model, alignment: .leading)
                    .padding(.leading, 30)
                HeaderCell(title: "CPU", key: .cpu, model: model, summary: TaskManagerFormat.percent(model.system.cpuPercent), width: Col.num)
                    .padding(.horizontal, 6)
                HeaderCell(title: tr("Bộ nhớ", "Memory"), key: .memory, model: model, summary: TaskManagerFormat.percent(model.system.memoryPercent), width: Col.num)
                    .padding(.horizontal, 6)
                HeaderCell(title: tr("Đĩa", "Disk"), key: .disk, model: model, summary: TaskManagerFormat.rate(model.system.diskReadPerSec + model.system.diskWritePerSec), width: Col.wide)
                    .padding(.horizontal, 6)
                HeaderCell(title: tr("Năng lượng", "Power"), key: .power, model: model, width: Col.num)
                    .padding(.horizontal, 6)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.primary.opacity(0.04))
            Divider()
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    sectionHeader(tr("Ứng dụng", "Apps"), count: sections.apps.count)
                    ForEach(sections.apps) { group in groupRows(group) }
                    sectionHeader(tr("Tiến trình nền", "Background processes"), count: sections.background.count)
                    ForEach(sections.background) { group in groupRows(group) }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        Text("\(title) (\(count))")
            .font(.system(size: FS.label, weight: .semibold))
            .foregroundStyle(Tone.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
    }

    @ViewBuilder
    private func groupRows(_ group: ProcessGroup) -> some View {
        let multi = group.rows.count > 1
        let isOpen = model.expanded.contains(group.id)
        GroupRow(group: group, multi: multi, isOpen: isOpen, selected: model.selectedGroupID == group.id && model.selectedPID == nil,
                 onToggle: {
                     if isOpen { model.expanded.remove(group.id) } else { model.expanded.insert(group.id) }
                 }, onSelect: {
                     model.selectedGroupID = group.id; model.selectedPID = nil
                 })
        .contextMenu { ProcessMenu(model: model, rows: group.rows, confirm: confirm) }
        if multi && isOpen {
            ForEach(ProcessGrouping.sort(group.rows, by: model.sortKey, ascending: model.sortAscending)) { row in
                ChildRow(row: row, selected: model.selectedPID == row.pid) {
                    model.selectedGroupID = group.id; model.selectedPID = row.pid
                }
                .contextMenu { ProcessMenu(model: model, rows: [row], confirm: confirm) }
            }
        }
    }
}

private struct GroupRow: View {
    let group: ProcessGroup
    let multi: Bool
    let isOpen: Bool
    let selected: Bool
    let onToggle: () -> Void
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Color.clear.frame(width: 12)
                    Image(nsImage: IconCache.shared.icon(forApp: group.appPath)).resizable().frame(width: 16, height: 16)
                    Text(group.name).font(.system(size: FS.body)).lineLimit(1)
                    if multi { Text("(\(group.rows.count))").font(.system(size: FS.label)).foregroundStyle(.secondary) }
                    if group.isStopped { Image(systemName: "pause.circle.fill").foregroundStyle(Tone.warn).help(tr("Đang tạm dừng", "Suspended")) }
                    Spacer(minLength: 4)
                }
                .padding(.leading, 12)
                NumCell(text: TaskManagerFormat.percent(group.cpuPercent), fraction: group.cpuPercent / 100)
                NumCell(text: TaskManagerFormat.bytes(group.memoryBytes), fraction: Double(group.memoryBytes) / Double(max(1, ProcessInfo.processInfo.physicalMemory)) * 4)
                NumCell(text: TaskManagerFormat.rate(group.diskPerSec), fraction: group.diskPerSec / 50_000_000, width: Col.wide)
                NumCell(text: TaskManagerFormat.power(group.powerMilliwatts), fraction: group.powerMilliwatts / 5000)
            }
            .padding(.horizontal, 8)
            .background(selected ? Tone.accent.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded { if multi { onToggle() } })
        .overlay(alignment: .leading) {
            if multi {
                Button(action: onToggle) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
        }
    }
}

private struct ChildRow: View {
    let row: ProcessRow
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text(row.name).font(.system(size: FS.label)).lineLimit(1)
                    Text("PID \(row.pid)").font(.system(size: FS.caption)).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                }
                .padding(.leading, 52)
                NumCell(text: TaskManagerFormat.percent(row.cpuPercent), fraction: row.cpuPercent / 100)
                NumCell(text: TaskManagerFormat.bytes(row.memoryBytes), fraction: Double(row.memoryBytes) / Double(max(1, ProcessInfo.processInfo.physicalMemory)) * 4)
                NumCell(text: TaskManagerFormat.rate(row.diskPerSec), fraction: row.diskPerSec / 50_000_000, width: Col.wide)
                NumCell(text: TaskManagerFormat.power(row.powerMilliwatts), fraction: row.powerMilliwatts / 5000)
            }
            .padding(.horizontal, 8)
            .foregroundStyle(.secondary)
            .background(selected ? Tone.accent.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Menu chuột phải dùng chung cho tab Tiến trình và Chi tiết.
private struct ProcessMenu: View {
    @ObservedObject var model: TaskManagerModel
    let rows: [ProcessRow]
    let confirm: (_ title: String, _ detail: String, _ label: String, _ run: @escaping () -> Void) -> Void

    var body: some View {
        let name = rows.count == 1 ? rows[0].name : tr("\(rows.count) tiến trình", "\(rows.count) processes")
        Button(tr("Kết thúc tác vụ", "End task")) {
            confirm(tr("Kết thúc \(name)?", "End \(name)?"),
                    tr("Tiến trình sẽ nhận yêu cầu thoát. Dữ liệu chưa lưu có thể mất.", "Processes will be asked to quit. Unsaved data may be lost."),
                    tr("Kết thúc", "End")) { model.endTask(rows) }
        }
        Button(tr("Buộc dừng", "Force quit")) {
            confirm(tr("Buộc dừng \(name)?", "Force quit \(name)?"),
                    tr("Tiến trình bị dừng ngay, dữ liệu chưa lưu sẽ mất.", "The process stops immediately; unsaved data is lost."),
                    tr("Buộc dừng", "Force quit")) { model.forceKill(rows) }
        }
        Divider()
        if rows.contains(where: { !$0.isStopped }) {
            Button(tr("Tạm dừng", "Suspend")) { model.suspend(rows) }
        }
        if rows.contains(where: { $0.isStopped }) {
            Button(tr("Tiếp tục", "Resume")) { model.resume(rows) }
        }
        if rows.count == 1 {
            Menu(tr("Độ ưu tiên", "Priority")) {
                Button(tr("Thấp (nice 10)", "Low (nice 10)")) { model.setNice(10, for: rows) }
                Button(tr("Bình thường (nice 0)", "Normal (nice 0)")) { model.setNice(0, for: rows) }
                Button(tr("Rất thấp (nice 20)", "Idle (nice 20)")) { model.setNice(20, for: rows) }
            }
            Divider()
            Button(tr("Mở vị trí trong Finder", "Reveal in Finder")) { model.revealInFinder(rows[0]) }
                .disabled(rows[0].path.isEmpty)
            Button(tr("Sao chép đường dẫn", "Copy path")) { model.copyPath(rows[0]) }
                .disabled(rows[0].path.isEmpty)
        }
    }
}

// MARK: - Tab Chi tiết

private struct DetailsPane: View {
    @ObservedObject var model: TaskManagerModel
    let confirm: (_ title: String, _ detail: String, _ label: String, _ run: @escaping () -> Void) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HeaderCell(title: tr("Tên", "Name"), key: .name, model: model, alignment: .leading).padding(.leading, 12)
                HeaderCell(title: "PID", key: .pid, model: model, width: Col.pid)
                Text(tr("Trạng thái", "Status")).font(.system(size: FS.label, weight: .medium)).frame(width: 84, alignment: .leading).padding(.leading, 10)
                HeaderCell(title: tr("Người dùng", "User"), key: .user, model: model, width: 96, alignment: .leading).padding(.leading, 6)
                HeaderCell(title: "CPU", key: .cpu, model: model, width: 64)
                HeaderCell(title: tr("Bộ nhớ", "Memory"), key: .memory, model: model, width: 84)
                HeaderCell(title: tr("Luồng", "Threads"), key: .threads, model: model, width: 56)
                HeaderCell(title: tr("Đĩa", "Disk"), key: .disk, model: model, width: 90)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.visibleRows) { row in
                        Button {
                            model.selectedPID = row.pid; model.selectedGroupID = nil
                        } label: {
                        HStack(spacing: 0) {
                            Text(row.name).font(.system(size: FS.body)).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12)
                            Text(String(row.pid)).monospacedDigit().frame(width: Col.pid, alignment: .trailing)
                            Text(status(row)).frame(width: 84, alignment: .leading).padding(.leading, 10)
                                .foregroundStyle(row.isStopped ? Tone.warn : .secondary)
                            Text(row.user).lineLimit(1).frame(width: 96, alignment: .leading).padding(.leading, 6).foregroundStyle(.secondary)
                            Text(row.isRestricted ? "—" : TaskManagerFormat.percent(row.cpuPercent)).monospacedDigit().frame(width: 64, alignment: .trailing)
                            Text(row.isRestricted ? "—" : TaskManagerFormat.bytes(row.memoryBytes)).monospacedDigit().frame(width: 84, alignment: .trailing)
                            Text(row.isRestricted ? "—" : String(row.threads)).monospacedDigit().frame(width: 56, alignment: .trailing)
                            Text(row.isRestricted ? "—" : TaskManagerFormat.rate(row.diskPerSec)).monospacedDigit().frame(width: 90, alignment: .trailing)
                        }
                        .font(.system(size: FS.body))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(model.selectedPID == row.pid ? Tone.accent.opacity(0.18) : Color.clear)
                        .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { ProcessMenu(model: model, rows: [row], confirm: confirm) }
                        .help(row.path)
                    }
                }
            }
            if let row = model.rows.first(where: { $0.pid == model.selectedPID }) {
                Divider()
                HStack(spacing: 16) {
                    Text(row.path.isEmpty ? tr("(không đọc được đường dẫn)", "(path unavailable)") : row.path)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Spacer()
                    Text("PPID \(row.ppid)")
                    Text("nice \(row.nice)")
                }
                .font(.system(size: FS.label)).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 5)
            }
        }
    }

    private func status(_ row: ProcessRow) -> String {
        row.isStopped ? tr("Tạm dừng", "Suspended") : (row.isRestricted ? tr("Hạn chế", "Restricted") : tr("Đang chạy", "Running"))
    }
}

// MARK: - Tab Hiệu năng

private struct PerformancePane: View {
    @ObservedObject var model: TaskManagerModel

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 6) {
                    card(.cpu, title: "CPU", subtitle: TaskManagerFormat.percent(model.system.cpuPercent),
                         history: model.cpuHistory, ceiling: 100, color: .blue)
                    card(.memory, title: tr("Bộ nhớ", "Memory"),
                         subtitle: "\(TaskManagerFormat.bytes(model.system.memoryUsed)) / \(TaskManagerFormat.bytes(model.system.memoryTotal))",
                         history: model.memoryHistory, ceiling: 100, color: .purple)
                    card(.disk, title: tr("Đĩa", "Disk"),
                         subtitle: "↓ \(TaskManagerFormat.rate(model.system.diskReadPerSec))  ↑ \(TaskManagerFormat.rate(model.system.diskWritePerSec))",
                         history: model.diskReadHistory, ceiling: nil, color: .green)
                    card(.network, title: tr("Mạng", "Network"),
                         subtitle: "↓ \(TaskManagerFormat.rate(model.system.netDownPerSec))  ↑ \(TaskManagerFormat.rate(model.system.netUpPerSec))",
                         history: model.netDownHistory, ceiling: nil, color: .orange)
                    if model.system.gpuPercent != nil {
                        card(.gpu, title: "GPU", subtitle: TaskManagerFormat.percent(model.system.gpuPercent ?? 0),
                             history: model.gpuHistory, ceiling: 100, color: .pink)
                    }
                }
                .padding(10)
            }
            .frame(width: 230)
            Divider()
            ScrollView { detail.padding(18) }
        }
    }

    private func card(_ pane: TaskManagerModel.PerformancePane, title: String, subtitle: String,
                      history: History, ceiling: Double?, color: Color) -> some View {
        Button { model.pane = pane } label: {
            HStack(spacing: 8) {
                GraphView(values: history.values, capacity: history.capacity, maxValue: ceiling ?? history.peak(floor: 1_048_576), color: color)
                    .frame(width: 64, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: FS.body, weight: .semibold))
                    Text(subtitle).font(.system(size: FS.label)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: Rad.sm).fill(model.pane == pane ? Tone.accent.opacity(0.16) : Color.primary.opacity(0.04)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        let s = model.system
        switch model.pane {
        case .cpu:
            VStack(alignment: .leading, spacing: 12) {
                header("CPU", big: TaskManagerFormat.percent(s.cpuPercent), caption: tr("Mức dùng 60 giây gần nhất", "Utilisation, last 60 seconds"))
                GraphView(values: model.cpuHistory.values, capacity: 60, maxValue: 100, color: .blue).frame(height: 190).bordered()
                Text(tr("Từng nhân", "Per core")).font(.system(size: FS.title, weight: .semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                    ForEach(Array(model.perCoreHistory.enumerated()), id: \.offset) { i, h in
                        VStack(alignment: .leading, spacing: 2) {
                            GraphView(values: h.values, capacity: 60, maxValue: 100, color: .blue).frame(height: 36).bordered()
                            Text(tr("Nhân \(i + 1): ", "Core \(i + 1): ") + TaskManagerFormat.percent(h.values.last ?? 0))
                                .font(.system(size: FS.caption)).foregroundStyle(.secondary)
                        }
                    }
                }
                stats([
                    (tr("Tiến trình", "Processes"), "\(s.processCount)"),
                    (tr("Luồng", "Threads"), "\(s.threadCount)"),
                    (tr("Số nhân", "Cores"), "\(s.perCorePercent.count)"),
                    (tr("Thời gian chạy", "Up time"), TaskManagerFormat.uptime(s.uptime)),
                ])
            }
        case .memory:
            VStack(alignment: .leading, spacing: 12) {
                header(tr("Bộ nhớ", "Memory"), big: "\(TaskManagerFormat.bytes(s.memoryUsed)) / \(TaskManagerFormat.bytes(s.memoryTotal))", caption: tr("Mức dùng 60 giây gần nhất", "Usage, last 60 seconds"))
                GraphView(values: model.memoryHistory.values, capacity: 60, maxValue: 100, color: .purple).frame(height: 190).bordered()
                stats([
                    (tr("Đang dùng", "In use"), TaskManagerFormat.bytes(s.memoryUsed)),
                    (tr("Wired", "Wired"), TaskManagerFormat.bytes(s.memoryWired)),
                    (tr("Đã nén", "Compressed"), TaskManagerFormat.bytes(s.memoryCompressed)),
                    (tr("Có thể thu hồi (cache)", "Cached files"), TaskManagerFormat.bytes(s.memoryCached)),
                    (tr("Swap", "Swap used"), "\(TaskManagerFormat.bytes(s.swapUsed)) / \(TaskManagerFormat.bytes(s.swapTotal))"),
                ])
            }
        case .disk:
            VStack(alignment: .leading, spacing: 12) {
                header(tr("Đĩa", "Disk"), big: "↓ \(TaskManagerFormat.rate(s.diskReadPerSec))   ↑ \(TaskManagerFormat.rate(s.diskWritePerSec))", caption: tr("Đọc (xanh) và ghi (cam)", "Read (green) and write (orange)"))
                DualGraph(a: model.diskReadHistory, b: model.diskWriteHistory, colorA: .green, colorB: .orange).frame(height: 190).bordered()
            }
        case .network:
            VStack(alignment: .leading, spacing: 12) {
                header(tr("Mạng", "Network"), big: "↓ \(TaskManagerFormat.rate(s.netDownPerSec))   ↑ \(TaskManagerFormat.rate(s.netUpPerSec))", caption: tr("Nhận (cam) và gửi (xanh dương), các cổng en*", "Receive (orange) and send (blue), en* interfaces"))
                DualGraph(a: model.netDownHistory, b: model.netUpHistory, colorA: .orange, colorB: .blue).frame(height: 190).bordered()
            }
        case .gpu:
            VStack(alignment: .leading, spacing: 12) {
                header("GPU", big: TaskManagerFormat.percent(s.gpuPercent ?? 0), caption: tr("Mức dùng 60 giây gần nhất", "Utilisation, last 60 seconds"))
                GraphView(values: model.gpuHistory.values, capacity: 60, maxValue: 100, color: .pink).frame(height: 190).bordered()
            }
        }
    }

    private func header(_ title: String, big: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: FS.subhead, weight: .semibold))
            Text(big).font(.system(size: FS.display, weight: .semibold).monospacedDigit())
            Text(caption).font(.system(size: FS.label)).foregroundStyle(.secondary)
        }
    }

    private func stats(_ items: [(String, String)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .topLeading)], alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.0).font(.system(size: FS.label)).foregroundStyle(.secondary)
                    Text(item.1).font(.system(size: FS.title, weight: .medium).monospacedDigit())
                }
            }
        }
    }
}

// MARK: - Đồ thị

private extension View {
    func bordered() -> some View {
        self.background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: Rad.sm).stroke(Color.primary.opacity(0.15), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Rad.sm))
    }
}

struct GraphView: View {
    let values: [Double]
    let capacity: Int
    let maxValue: Double
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1, maxValue > 0 else { return }
            let step = size.width / CGFloat(max(1, capacity - 1))
            let startX = size.width - step * CGFloat(values.count - 1)
            var line = Path()
            for (i, v) in values.enumerated() {
                let x = startX + step * CGFloat(i)
                let y = size.height - CGFloat(min(max(v / maxValue, 0), 1)) * (size.height - 1)
                if i == 0 { line.move(to: CGPoint(x: x, y: y)) } else { line.addLine(to: CGPoint(x: x, y: y)) }
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: startX, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(color.opacity(0.22)))
            ctx.stroke(line, with: .color(color), lineWidth: 1.4)
        }
    }
}

private struct DualGraph: View {
    let a: History
    let b: History
    let colorA: Color
    let colorB: Color
    var body: some View {
        let peak = max(a.peak(floor: 1_048_576), b.peak(floor: 1_048_576))
        ZStack(alignment: .topLeading) {
            GraphView(values: a.values, capacity: a.capacity, maxValue: peak, color: colorA)
            GraphView(values: b.values, capacity: b.capacity, maxValue: peak, color: colorB)
            Text(TaskManagerFormat.rate(peak)).font(.system(size: FS.caption)).foregroundStyle(.secondary).padding(4)
        }
    }
}
