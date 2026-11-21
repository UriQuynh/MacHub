// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import Foundation
import Darwin

/// Số liệu toàn hệ thống tại một thời điểm.
struct SystemSnapshot: Equatable {
    var cpuPercent: Double = 0
    var perCorePercent: [Double] = []
    var memoryTotal: UInt64 = 0
    var memoryUsed: UInt64 = 0
    var memoryWired: UInt64 = 0
    var memoryCompressed: UInt64 = 0
    var memoryCached: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var diskReadPerSec: Double = 0
    var diskWritePerSec: Double = 0
    var netDownPerSec: Double = 0
    var netUpPerSec: Double = 0
    var gpuPercent: Double?
    var processCount: Int = 0
    var threadCount: Int = 0
    var uptime: TimeInterval = 0

    var memoryPercent: Double { memoryTotal == 0 ? 0 : Double(memoryUsed) / Double(memoryTotal) * 100 }
}

/// Vòng đệm cố định N giá trị gần nhất cho đồ thị.
struct History: Equatable {
    let capacity: Int
    private(set) var values: [Double] = []
    init(capacity: Int = 60) { self.capacity = capacity }
    mutating func append(_ value: Double) {
        values.append(value)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }
    /// Giá trị lớn nhất, tối thiểu `floor`, để thang đồ thị không co về 0.
    func peak(floor: Double) -> Double { max(values.max() ?? 0, floor) }
}

/// Đọc CPU từng nhân, RAM, đĩa, mạng, GPU. Có trạng thái (mốc trước) nên chỉ dùng trên một queue.
final class SystemSampler {
    private struct CoreTicks { var user: UInt32; var sys: UInt32; var idle: UInt32; var nice: UInt32 }

    private var previousCores: [CoreTicks] = []
    private var previousDisk: [String: (r: UInt64, w: UInt64)] = [:]
    private var previousNet: [String: (r: UInt64, w: UInt64)] = [:]
    private var previousAt: UInt64 = 0

    private static let hostPort: mach_port_t = mach_host_self()

    func reset() {
        previousCores = []
        previousDisk = [:]
        previousNet = [:]
        previousAt = 0
    }

    func sample(nowNs: UInt64, processCount: Int, threadCount: Int) -> SystemSnapshot {
        var snap = SystemSnapshot()
        let seconds = previousAt == 0 ? 0 : Double(nowNs &- previousAt) / 1_000_000_000

        // CPU từng nhân
        let cores = Self.readCores()
        if !previousCores.isEmpty, previousCores.count == cores.count {
            var perCore: [Double] = []
            var active: UInt64 = 0, total: UInt64 = 0
            for (now, before) in zip(cores, previousCores) {
                let user = UInt64(now.user &- before.user)
                let sys = UInt64(now.sys &- before.sys)
                let idle = UInt64(now.idle &- before.idle)
                let nice = UInt64(now.nice &- before.nice)
                let used = user + sys + nice
                let sum = used + idle
                perCore.append(sum == 0 ? 0 : Double(used) / Double(sum) * 100)
                active += used
                total += sum
            }
            snap.perCorePercent = perCore
            snap.cpuPercent = total == 0 ? 0 : Double(active) / Double(total) * 100
        } else {
            snap.perCorePercent = [Double](repeating: 0, count: cores.count)
        }
        previousCores = cores

        Self.fillMemory(&snap)

        // Đĩa (tổng các ổ vật lý) và mạng (en*)
        let disks = DiskSpeedSampler.readDiskCounters().0
        let net = DiskSpeedSampler.readInterfaceCounters().filter { DiskSpeedSampler.isPhysicalInterface($0.key) }
        if seconds > 0 {
            snap.diskReadPerSec = Self.rate(disks, previousDisk, seconds, \.r)
            snap.diskWritePerSec = Self.rate(disks, previousDisk, seconds, \.w)
            snap.netDownPerSec = Self.rate(net, previousNet, seconds, \.r)
            snap.netUpPerSec = Self.rate(net, previousNet, seconds, \.w)
        }
        previousDisk = disks
        previousNet = net
        previousAt = nowNs

        snap.gpuPercent = SystemMonitorManager.readGPUUtilization()
        snap.processCount = processCount
        snap.threadCount = threadCount
        snap.uptime = ProcessInfo.processInfo.systemUptime
        return snap
    }

    private static func rate(_ now: [String: (r: UInt64, w: UInt64)], _ before: [String: (r: UInt64, w: UInt64)],
                             _ seconds: Double, _ field: KeyPath<(r: UInt64, w: UInt64), UInt64>) -> Double {
        var sum: UInt64 = 0
        for (name, value) in now {
            guard let old = before[name] else { continue }
            let a = value[keyPath: field], b = old[keyPath: field]
            if a >= b { sum += a - b }
        }
        return Double(sum) / seconds
    }

    private static func readCores() -> [CoreTicks] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(hostPort, PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        return (0..<Int(count)).map { i in
            let base = i * Int(CPU_STATE_MAX)
            return CoreTicks(user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                             sys: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                             idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                             nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
        }
    }

    private static func fillMemory(_ snap: inout SystemSnapshot) {
        snap.memoryTotal = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            let appPages = stats.internal_page_count >= stats.purgeable_count
                ? UInt64(stats.internal_page_count - stats.purgeable_count) : 0
            snap.memoryWired = UInt64(stats.wire_count) * page
            snap.memoryCompressed = UInt64(stats.compressor_page_count) * page
            snap.memoryUsed = min(snap.memoryTotal, appPages * page + snap.memoryWired + snap.memoryCompressed)
            snap.memoryCached = (UInt64(stats.external_page_count) + UInt64(stats.purgeable_count)) * page
        }
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            snap.swapUsed = swap.xsu_used
            snap.swapTotal = swap.xsu_total
        }
    }
}

// MARK: - Định dạng

enum TaskManagerFormat {
    static func bytes(_ value: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(value)
        var i = 0
        while v >= 1024, i < units.count - 1 { v /= 1024; i += 1 }
        return i == 0 ? "\(Int(v)) B" : String(format: v >= 100 ? "%.0f %@" : "%.1f %@", v, units[i])
    }

    static func rate(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 { return bytesPerSec < 1 ? "0 B/s" : String(format: "%.0f B/s", bytesPerSec) }
        return bytes(UInt64(bytesPerSec)) + "/s"
    }

    static func percent(_ value: Double) -> String {
        value < 0.05 ? "0%" : (value < 10 ? String(format: "%.1f%%", value) : String(format: "%.0f%%", value))
    }

    static func power(_ milliwatts: Double) -> String {
        milliwatts < 1 ? "0 mW" : (milliwatts >= 1000 ? String(format: "%.1f W", milliwatts / 1000) : String(format: "%.0f mW", milliwatts))
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        return d > 0 ? String(format: "%d:%02d:%02d", d, h, m) : String(format: "%d:%02d", h, m)
    }
}
