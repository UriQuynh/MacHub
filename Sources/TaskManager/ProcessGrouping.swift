// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import Foundation

/// Một nhóm hiển thị: một ứng dụng (gồm các tiến trình helper) hoặc một tiến trình nền đơn lẻ.
struct ProcessGroup: Identifiable, Equatable {
    var id: String
    var name: String
    /// Đường dẫn `.app` nếu là ứng dụng; nil nếu là tiến trình nền.
    var appPath: String?
    var rows: [ProcessRow]
    /// true nếu là ứng dụng người dùng mở (có Dock icon); false là tiến trình nền/dịch vụ.
    var isApp: Bool
    var cpuPercent: Double { rows.reduce(0) { $0 + $1.cpuPercent } }
    var memoryBytes: UInt64 { rows.reduce(0) { $0 + $1.memoryBytes } }
    var diskReadPerSec: Double { rows.reduce(0) { $0 + $1.diskReadPerSec } }
    var diskWritePerSec: Double { rows.reduce(0) { $0 + $1.diskWritePerSec } }
    var diskPerSec: Double { diskReadPerSec + diskWritePerSec }
    var powerMilliwatts: Double { rows.reduce(0) { $0 + $1.powerMilliwatts } }
    var threads: Int32 { rows.reduce(0) { $0 + $1.threads } }
    var pids: [Int32] { rows.map(\.pid) }
    var isStopped: Bool { !rows.isEmpty && rows.allSatisfy(\.isStopped) }
}

enum ProcessSortKey: String, CaseIterable {
    case name, cpu, memory, disk, power, pid, user, threads
}

enum ProcessGrouping {
    /// Gói `.app` ngoài cùng của một đường dẫn thực thi.
    /// `/Applications/Google Chrome.app/Contents/Frameworks/.../Helper.app/Contents/MacOS/x`
    /// → `/Applications/Google Chrome.app`.
    static func appBundlePath(forExecutable path: String) -> String? {
        guard let range = path.range(of: ".app/") else {
            return path.hasSuffix(".app") ? path : nil
        }
        return String(path[..<range.upperBound].dropLast())
    }

    static func appName(forBundlePath path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// Gom danh sách phẳng thành các nhóm. Tiến trình không thuộc app nào là một nhóm một dòng.
    /// `userAppPIDs`: các pid của app có giao diện (NSRunningApplication `.regular`). Nil = chỉ dựa vào đường dẫn `.app`.
    static func group(_ rows: [ProcessRow], userAppPIDs: Set<Int32>? = nil) -> [ProcessGroup] {
        var order: [String] = []
        var byKey: [String: ProcessGroup] = [:]
        for row in rows {
            let key: String
            let name: String
            let appPath = row.appBundlePath
            if let appPath {
                key = "app:" + appPath
                name = appName(forBundlePath: appPath)
            } else {
                key = "pid:\(row.pid)"
                name = row.name
            }
            if byKey[key] == nil {
                order.append(key)
                byKey[key] = ProcessGroup(id: key, name: name, appPath: appPath, rows: [], isApp: appPath != nil && userAppPIDs == nil)
            }
            byKey[key]?.rows.append(row)
            if let userAppPIDs, userAppPIDs.contains(row.pid) { byKey[key]?.isApp = true }
        }
        return order.compactMap { byKey[$0] }
    }

    static func filter(_ groups: [ProcessGroup], query: String) -> [ProcessGroup] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return groups }
        return groups.compactMap { group in
            if group.name.lowercased().contains(q) { return group }
            let hits = group.rows.filter {
                $0.name.lowercased().contains(q) || String($0.pid) == q || $0.path.lowercased().contains(q)
            }
            guard !hits.isEmpty else { return nil }
            var copy = group
            copy.rows = hits
            return copy
        }
    }

    static func sort(_ groups: [ProcessGroup], by key: ProcessSortKey, ascending: Bool) -> [ProcessGroup] {
        func less(_ a: ProcessGroup, _ b: ProcessGroup) -> Bool {
            switch key {
            case .name: return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .cpu: return a.cpuPercent < b.cpuPercent
            case .memory: return a.memoryBytes < b.memoryBytes
            case .disk: return a.diskPerSec < b.diskPerSec
            case .power: return a.powerMilliwatts < b.powerMilliwatts
            case .threads: return a.threads < b.threads
            case .pid: return (a.rows.map(\.pid).min() ?? 0) < (b.rows.map(\.pid).min() ?? 0)
            case .user: return (a.rows.first?.user ?? "") < (b.rows.first?.user ?? "")
            }
        }
        return groups.sorted { ascending ? less($0, $1) : less($1, $0) }
    }

    static func sort(_ rows: [ProcessRow], by key: ProcessSortKey, ascending: Bool) -> [ProcessRow] {
        func less(_ a: ProcessRow, _ b: ProcessRow) -> Bool {
            switch key {
            case .name: return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .cpu: return a.cpuPercent < b.cpuPercent
            case .memory: return a.memoryBytes < b.memoryBytes
            case .disk: return a.diskPerSec < b.diskPerSec
            case .power: return a.powerMilliwatts < b.powerMilliwatts
            case .threads: return a.threads < b.threads
            case .pid: return a.pid < b.pid
            case .user: return a.user < b.user
            }
        }
        return rows.sorted { ascending ? less($0, $1) : less($1, $0) }
    }
}

// MARK: - An toàn khi kết thúc tác vụ

enum ProcessSafety {
    /// Tiến trình mà việc dừng nó làm treo hoặc đăng xuất cả phiên: không cho kết thúc từ Task Manager.
    static let protectedNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "launchservicesd", "coreservicesd",
    ]

    enum Verdict: Equatable {
        case allowed
        case protectedSystem
        case itself
        case needsAdmin
    }

    static func verdict(for row: ProcessRow, selfPID: Int32 = getpid(), currentUID: UInt32 = getuid()) -> Verdict {
        if row.pid == selfPID { return .itself }
        if row.pid <= 1 || protectedNames.contains(row.name) { return .protectedSystem }
        if row.uid != currentUID && currentUID != 0 { return .needsAdmin }
        return .allowed
    }
}
