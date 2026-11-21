// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import AppKit
import Combine
import Darwin

/// Trạng thái và hành động của cửa sổ Task Manager.
/// Chỉ đọc số liệu khi cửa sổ đang mở (`start()` / `stop()`) để giữ 0% CPU lúc rảnh.
@MainActor
final class TaskManagerModel: ObservableObject {
    static let shared = TaskManagerModel()

    enum Section: Int, CaseIterable { case processes, performance, details }
    enum PerformancePane: String, CaseIterable { case cpu, memory, disk, network, gpu }

    @Published var section: Section = .processes
    @Published var pane: PerformancePane = .cpu
    @Published var search = ""
    @Published var sortKey: ProcessSortKey = .cpu
    @Published var sortAscending = false
    @Published var expanded: Set<String> = []
    /// pid đang chọn (ở tab Chi tiết) hoặc id nhóm (ở tab Tiến trình).
    @Published var selectedGroupID: String?
    @Published var selectedPID: Int32?
    @Published var message: String?

    @Published private(set) var rows: [ProcessRow] = []
    @Published private(set) var groups: [ProcessGroup] = []
    @Published private(set) var system = SystemSnapshot()
    @Published private(set) var cpuHistory = History()
    @Published private(set) var memoryHistory = History()
    @Published private(set) var diskReadHistory = History()
    @Published private(set) var diskWriteHistory = History()
    @Published private(set) var netDownHistory = History()
    @Published private(set) var netUpHistory = History()
    @Published private(set) var gpuHistory = History()
    @Published private(set) var perCoreHistory: [History] = []

    var interval: TimeInterval = 2.0

    private let queue = DispatchQueue(label: "com.machub.taskmanager", qos: .userInitiated)
    private let table = ProcessTable()
    private let sampler = SystemSampler()
    private var timer: Timer?
    private var isSampling = false
    private var generation = 0

    private init() {}

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        generation += 1
        tick()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        generation += 1
        queue.async { [table, sampler] in
            table.reset()
            sampler.reset()
        }
    }

    func refreshNow() { tick() }

    private func tick() {
        guard !isSampling else { return }
        isSampling = true
        let gen = generation
        queue.async { [table, sampler] in
            let now = DispatchTime.now().uptimeNanoseconds
            let raw = ProcessSampler.readAll()
            let rows = table.update(samples: raw, nowNs: now)
            let threads = rows.reduce(0) { $0 + Int($1.threads) }
            let snap = sampler.sample(nowNs: now, processCount: rows.count, threadCount: threads)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    guard let self else { return }
                    self.isSampling = false
                    guard gen == self.generation else { return }
                    self.apply(rows: rows, system: snap)
                }
            }
        }
    }

    private func apply(rows: [ProcessRow], system snap: SystemSnapshot) {
        self.rows = rows
        let appPIDs = Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(\.processIdentifier))
        self.groups = ProcessGrouping.group(rows, userAppPIDs: appPIDs)
        self.system = snap
        cpuHistory.append(snap.cpuPercent)
        memoryHistory.append(snap.memoryPercent)
        diskReadHistory.append(snap.diskReadPerSec)
        diskWriteHistory.append(snap.diskWritePerSec)
        netDownHistory.append(snap.netDownPerSec)
        netUpHistory.append(snap.netUpPerSec)
        gpuHistory.append(snap.gpuPercent ?? 0)
        if perCoreHistory.count != snap.perCorePercent.count {
            perCoreHistory = snap.perCorePercent.map { _ in History() }
        }
        for (i, value) in snap.perCorePercent.enumerated() { perCoreHistory[i].append(value) }
    }

    // MARK: Dữ liệu cho view

    /// Nhóm đã lọc + sắp xếp, tách thành Ứng dụng / Tiến trình nền như Task Manager.
    var visibleGroups: (apps: [ProcessGroup], background: [ProcessGroup]) {
        let filtered = ProcessGrouping.filter(groups, query: search)
        let sorted = ProcessGrouping.sort(filtered, by: sortKey, ascending: sortAscending)
        return (sorted.filter(\.isApp), sorted.filter { !$0.isApp })
    }

    var visibleRows: [ProcessRow] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = q.isEmpty ? rows : rows.filter {
            $0.name.lowercased().contains(q) || String($0.pid) == q || $0.path.lowercased().contains(q) || $0.user.lowercased().contains(q)
        }
        return ProcessGrouping.sort(filtered, by: sortKey, ascending: sortAscending)
    }

    func toggleSort(_ key: ProcessSortKey) {
        if sortKey == key { sortAscending.toggle() } else {
            sortKey = key
            sortAscending = key == .name || key == .pid || key == .user
        }
    }

    func selectedRows() -> [ProcessRow] {
        switch section {
        case .details:
            return rows.filter { $0.pid == selectedPID }
        default:
            if let id = selectedGroupID, let group = groups.first(where: { $0.id == id }) { return group.rows }
            if let pid = selectedPID { return rows.filter { $0.pid == pid } }
            return []
        }
    }

    // MARK: Hành động

    /// Kết thúc nhẹ nhàng (SIGTERM, hoặc `terminate()` với app có giao diện để hỏi lưu).
    func endTask(_ targets: [ProcessRow]) { signal(targets, force: false) }
    /// Buộc dừng ngay (SIGKILL).
    func forceKill(_ targets: [ProcessRow]) { signal(targets, force: true) }

    private func signal(_ targets: [ProcessRow], force: Bool) {
        var blocked: [String] = []
        var failed: [String] = []
        var done = 0
        for row in targets {
            switch ProcessSafety.verdict(for: row) {
            case .protectedSystem, .itself:
                blocked.append(row.name)
                continue
            case .needsAdmin:
                failed.append(row.name + " (" + tr("cần quyền quản trị", "needs admin") + ")")
                continue
            case .allowed:
                break
            }
            if !force, let app = NSRunningApplication(processIdentifier: row.pid), app.activationPolicy == .regular {
                if app.terminate() { done += 1 } else { failed.append(row.name) }
                continue
            }
            if Darwin.kill(row.pid, force ? SIGKILL : SIGTERM) == 0 { done += 1 } else { failed.append(row.name) }
        }
        var parts: [String] = []
        if done > 0 { parts.append(tr("Đã gửi lệnh dừng tới \(done) tiến trình.", "Sent stop request to \(done) process(es).")) }
        if !blocked.isEmpty { parts.append(tr("Không thể dừng (hệ thống): ", "Protected: ") + Set(blocked).sorted().joined(separator: ", ")) }
        if !failed.isEmpty { parts.append(tr("Thất bại: ", "Failed: ") + failed.joined(separator: ", ")) }
        message = parts.joined(separator: " ")
        appLog("TaskManager: \(force ? "kill" : "end") \(targets.map { "\($0.name)(\($0.pid))" }.joined(separator: ",")) -> \(message ?? "")")
        scheduleRefresh()
    }

    func suspend(_ targets: [ProcessRow]) { send(SIGSTOP, to: targets) }
    func resume(_ targets: [ProcessRow]) { send(SIGCONT, to: targets) }

    private func send(_ sig: Int32, to targets: [ProcessRow]) {
        for row in targets where ProcessSafety.verdict(for: row) == .allowed {
            // Không tạm dừng app đang ở phía trước: người dùng sẽ tưởng máy treo.
            if sig == SIGSTOP, NSWorkspace.shared.frontmostApplication?.processIdentifier == row.pid { continue }
            _ = Darwin.kill(row.pid, sig)
        }
        scheduleRefresh()
    }

    /// Đổi độ ưu tiên (nice -20…20). Hạ ưu tiên được với tiến trình của mình; tăng cần quyền root.
    func setNice(_ value: Int32, for targets: [ProcessRow]) {
        var failed = 0
        for row in targets where ProcessSafety.verdict(for: row) == .allowed {
            if setpriority(PRIO_PROCESS, id_t(row.pid), value) != 0 { failed += 1 }
        }
        message = failed == 0 ? nil : tr("Không đổi được độ ưu tiên (cần quyền quản trị để tăng).", "Could not change priority (admin needed to raise).")
        scheduleRefresh()
    }

    func revealInFinder(_ row: ProcessRow) {
        let path = row.appBundlePath ?? row.path
        guard !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func copyPath(_ row: ProcessRow) {
        guard !row.path.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(row.path, forType: .string)
    }

    private func scheduleRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
    }
}
