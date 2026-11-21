// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import Foundation
import Darwin

// MARK: - Dữ liệu thô của một tiến trình

/// Một lần đọc thô (chưa quy ra tốc độ) của một tiến trình, lấy từ `libproc`.
struct RawProcessSample: Equatable {
    var pid: Int32
    var ppid: Int32
    var uid: UInt32
    var name: String
    var path: String
    /// Thời điểm tiến trình bắt đầu (giây); cùng pid nhưng khác giá trị này nghĩa là pid đã bị dùng lại.
    var startTime: UInt64
    /// Tổng thời gian CPU (user + system), nano giây.
    var cpuTimeNs: UInt64
    /// Bộ nhớ thực tế tiến trình đang chiếm (phys_footprint, giống Activity Monitor).
    var footprintBytes: UInt64
    var threads: Int32
    var diskReadBytes: UInt64
    var diskWriteBytes: UInt64
    /// Năng lượng tiêu thụ cộng dồn, nano-joule.
    var energyNJ: UInt64
    var isStopped: Bool
    var nice: Int32
    /// true nếu không đọc được CPU/RAM (tiến trình của user khác hoặc root, cần quyền admin).
    var isRestricted: Bool
}

/// Một dòng đã tính tốc độ, sẵn sàng hiển thị.
struct ProcessRow: Identifiable, Equatable {
    var id: Int32 { pid }
    var pid: Int32
    var ppid: Int32
    var name: String
    var path: String
    var user: String
    var uid: UInt32
    /// % CPU theo toàn máy (0–100), giống cột CPU của Task Manager Windows.
    var cpuPercent: Double
    var memoryBytes: UInt64
    var diskReadPerSec: Double
    var diskWritePerSec: Double
    /// Công suất ước tính, miliwatt.
    var powerMilliwatts: Double
    var threads: Int32
    var isStopped: Bool
    var isRestricted: Bool
    var nice: Int32

    var diskPerSec: Double { diskReadPerSec + diskWritePerSec }

    /// Đường dẫn gói `.app` ngoài cùng chứa tiến trình (gom helper của Chrome, Slack... về một app).
    var appBundlePath: String? { ProcessGrouping.appBundlePath(forExecutable: path) }
}

// MARK: - Đọc libproc

enum ProcessSampler {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info.denom == 0 ? mach_timebase_info_data_t(numer: 1, denom: 1) : info
    }()

    /// Đổi đơn vị thời gian mach sang nano giây (trên Apple Silicon khác 1:1).
    static func machToNs(_ ticks: UInt64) -> UInt64 {
        machToNs(ticks, numer: UInt64(timebase.numer), denom: UInt64(timebase.denom))
    }

    /// Tách phần nguyên và phần dư để không tràn UInt64 với thời gian CPU dài.
    static func machToNs(_ ticks: UInt64, numer: UInt64, denom: UInt64) -> UInt64 {
        guard denom != 0, numer != denom else { return ticks }
        return (ticks / denom) &* numer &+ (ticks % denom) &* numer / denom
    }

    static func listPIDs() -> [Int32] {
        let estimated = proc_listallpids(nil, 0)
        guard estimated > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimated) + 128)
        let bytes = Int32(pids.count * MemoryLayout<pid_t>.size)
        let count = proc_listallpids(&pids, bytes)
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count))).filter { $0 > 0 }
    }

    static func readAll() -> [RawProcessSample] {
        listPIDs().compactMap { read(pid: $0) }
    }

    static func read(pid: Int32) -> RawProcessSample? {
        var task = proc_taskallinfo()
        let taskSize = Int32(MemoryLayout<proc_taskallinfo>.size)
        let gotTask = proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &task, taskSize) == taskSize

        var bsd: proc_bsdinfo
        if gotTask {
            bsd = task.pbsd
        } else {
            bsd = proc_bsdinfo()
            let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
            if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize) != bsdSize {
                // Tiến trình của root/user khác: chỉ đọc được bản rút gọn (ppid, uid, trạng thái, tên 16 ký tự).
                var short = proc_bsdshortinfo()
                let shortSize = Int32(MemoryLayout<proc_bsdshortinfo>.size)
                guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &short, shortSize) == shortSize else { return nil }
                bsd = proc_bsdinfo()
                bsd.pbi_ppid = short.pbsi_ppid
                bsd.pbi_uid = short.pbsi_uid
                bsd.pbi_status = short.pbsi_status
                bsd.pbi_comm = short.pbsi_comm
            }
        }

        var name = cString(bsd.pbi_name)
        if name.isEmpty { name = cString(bsd.pbi_comm) }
        let path = executablePath(pid: pid)
        if name.isEmpty { name = (path as NSString).lastPathComponent }

        var cpuNs: UInt64 = 0
        var footprint: UInt64 = 0
        var threads: Int32 = 0
        if gotTask {
            cpuNs = machToNs(task.ptinfo.pti_total_user &+ task.ptinfo.pti_total_system)
            footprint = task.ptinfo.pti_resident_size
            threads = task.ptinfo.pti_threadnum
        }

        var diskRead: UInt64 = 0
        var diskWrite: UInt64 = 0
        var energy: UInt64 = 0
        var usage = rusage_info_v6()
        let rc = withUnsafeMutablePointer(to: &usage) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
        }
        if rc == 0 {
            footprint = usage.ri_phys_footprint
            diskRead = usage.ri_diskio_bytesread
            diskWrite = usage.ri_diskio_byteswritten
            energy = usage.ri_energy_nj
            cpuNs = machToNs(usage.ri_user_time &+ usage.ri_system_time)
        }

        return RawProcessSample(
            pid: pid,
            ppid: Int32(bitPattern: bsd.pbi_ppid),
            uid: bsd.pbi_uid,
            name: name,
            path: path,
            startTime: bsd.pbi_start_tvsec,
            cpuTimeNs: cpuNs,
            footprintBytes: footprint,
            threads: threads,
            diskReadBytes: diskRead,
            diskWriteBytes: diskWrite,
            energyNJ: energy,
            isStopped: bsd.pbi_status == UInt32(SSTOP),
            nice: bsd.pbi_nice,
            isRestricted: !gotTask && rc != 0
        )
    }

    static func executablePath(pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return n > 0 ? String(cString: buffer) : ""
    }

    private static func cString<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

// MARK: - Tính tốc độ giữa hai lần đọc

/// Giữ lần đọc trước để tính CPU %, tốc độ đĩa và công suất. Chỉ dùng trên một queue.
final class ProcessTable {
    private var previous: [Int32: RawProcessSample] = [:]
    private var previousAt: UInt64 = 0
    private var userNames: [UInt32: String] = [:]
    let coreCount: Int

    init(coreCount: Int = ProcessInfo.processInfo.activeProcessorCount) {
        self.coreCount = max(1, coreCount)
    }

    /// `nowNs`: đồng hồ đơn điệu (nano giây). Lần gọi đầu CPU/đĩa = 0 vì chưa có mốc so sánh.
    func update(samples: [RawProcessSample], nowNs: UInt64) -> [ProcessRow] {
        let elapsed = previousAt == 0 ? 0 : nowNs &- previousAt
        let rows = samples.map { sample -> ProcessRow in
            let before = previous[sample.pid].flatMap { $0.startTime == sample.startTime ? $0 : nil }
            return Self.makeRow(current: sample, previous: before, elapsedNs: elapsed,
                                coreCount: coreCount, user: userName(sample.uid))
        }
        previous = Dictionary(samples.map { ($0.pid, $0) }, uniquingKeysWith: { _, new in new })
        previousAt = nowNs
        return rows
    }

    func reset() {
        previous = [:]
        previousAt = 0
    }

    /// Thuần hàm để kiểm thử: không đụng hệ thống.
    static func makeRow(current: RawProcessSample, previous: RawProcessSample?, elapsedNs: UInt64,
                        coreCount: Int, user: String) -> ProcessRow {
        var cpu = 0.0, readRate = 0.0, writeRate = 0.0, mw = 0.0
        if let previous, elapsedNs > 0 {
            let seconds = Double(elapsedNs) / 1_000_000_000
            let cpuDelta = current.cpuTimeNs >= previous.cpuTimeNs ? current.cpuTimeNs - previous.cpuTimeNs : 0
            cpu = Double(cpuDelta) / Double(elapsedNs) * 100.0 / Double(max(1, coreCount))
            cpu = min(max(cpu, 0), 100)
            readRate = Double(delta(current.diskReadBytes, previous.diskReadBytes)) / seconds
            writeRate = Double(delta(current.diskWriteBytes, previous.diskWriteBytes)) / seconds
            // nJ / giây = nW; chia 1e6 ra mW.
            mw = Double(delta(current.energyNJ, previous.energyNJ)) / seconds / 1_000_000
        }
        return ProcessRow(
            pid: current.pid, ppid: current.ppid, name: current.name, path: current.path,
            user: user, uid: current.uid, cpuPercent: cpu, memoryBytes: current.footprintBytes,
            diskReadPerSec: readRate, diskWritePerSec: writeRate, powerMilliwatts: mw,
            threads: current.threads, isStopped: current.isStopped,
            isRestricted: current.isRestricted, nice: current.nice
        )
    }

    private static func delta(_ now: UInt64, _ before: UInt64) -> UInt64 { now >= before ? now - before : 0 }

    private func userName(_ uid: UInt32) -> String {
        if let cached = userNames[uid] { return cached }
        var name = String(uid)
        if let pw = getpwuid(uid_t(uid)), let cname = pw.pointee.pw_name { name = String(cString: cname) }
        userNames[uid] = name
        return name
    }
}
