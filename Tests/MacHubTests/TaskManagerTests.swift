// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import XCTest
@testable import MacHub

final class TaskManagerTests: XCTestCase {
    // MARK: Helpers

    private func raw(pid: Int32 = 100, name: String = "proc", path: String = "/usr/bin/proc", start: UInt64 = 1,
                     cpuNs: UInt64 = 0, mem: UInt64 = 1000, read: UInt64 = 0, write: UInt64 = 0,
                     energy: UInt64 = 0, uid: UInt32 = 501) -> RawProcessSample {
        RawProcessSample(pid: pid, ppid: 1, uid: uid, name: name, path: path, startTime: start,
                         cpuTimeNs: cpuNs, footprintBytes: mem, threads: 2, diskReadBytes: read,
                         diskWriteBytes: write, energyNJ: energy, isStopped: false, nice: 0, isRestricted: false)
    }

    private func row(pid: Int32 = 100, name: String = "proc", path: String = "/usr/bin/proc",
                     cpu: Double = 0, mem: UInt64 = 0, uid: UInt32 = 501) -> ProcessRow {
        ProcessTable.makeRow(current: raw(pid: pid, name: name, path: path, cpuNs: 0, mem: mem, uid: uid),
                             previous: nil, elapsedNs: 0, coreCount: 4, user: "u")
            .with(cpu: cpu)
    }

    // MARK: libproc thật

    func testReadsOwnProcess() throws {
        let me = try XCTUnwrap(ProcessSampler.read(pid: getpid()))
        XCTAssertEqual(me.pid, getpid())
        XCTAssertFalse(me.name.isEmpty)
        XCTAssertFalse(me.path.isEmpty)
        XCTAssertEqual(me.uid, getuid())
        XCTAssertGreaterThan(me.footprintBytes, 0)
        XCTAssertGreaterThanOrEqual(me.threads, 1)
        XCTAssertGreaterThan(me.cpuTimeNs, 0)
        XCTAssertFalse(me.isRestricted)
        XCTAssertFalse(me.isStopped)
    }

    func testReadAllContainsSelfAndLaunchd() {
        let all = ProcessSampler.readAll()
        XCTAssertGreaterThan(all.count, 20)
        XCTAssertTrue(all.contains { $0.pid == getpid() })
        XCTAssertTrue(all.contains { $0.pid == 1 }, "launchd (pid 1) phải có trong danh sách dù không đọc được CPU")
    }

    func testBusyThreadShowsAboutOneCoreOfCPU() throws {
        let table = ProcessTable()
        let pid = getpid()
        _ = table.update(samples: [try XCTUnwrap(ProcessSampler.read(pid: pid))],
                         nowNs: DispatchTime.now().uptimeNanoseconds)
        let stop = Date().addingTimeInterval(1.2)
        let spinner = Thread {
            var x = 0.0
            while Date() < stop { x += sin(x) + 1 }
            _ = x
        }
        spinner.start()
        Thread.sleep(forTimeInterval: 1.25)
        let after = try XCTUnwrap(ProcessSampler.read(pid: pid))
        let rows = table.update(samples: [after], nowNs: DispatchTime.now().uptimeNanoseconds)
        let cpu = try XCTUnwrap(rows.first?.cpuPercent)
        let oneCore = 100.0 / Double(table.coreCount)
        // Một luồng bận ≈ 1 nhân (trừ ~4% thời gian ngủ thêm). Dung sai rộng để ổn định trên CI.
        XCTAssertGreaterThan(cpu, oneCore * 0.5, "CPU% quá thấp: đơn vị thời gian mach có thể sai")
        XCTAssertLessThan(cpu, oneCore * 1.8 + 5, "CPU% quá cao: đơn vị thời gian mach có thể sai")
    }

    // MARK: Tính tốc độ

    func testMakeRowComputesRatesNormalizedByCores() {
        let before = raw(cpuNs: 1_000_000_000, read: 1000, write: 0, energy: 0)
        let now = raw(cpuNs: 2_000_000_000, read: 3000, write: 4000, energy: 2_000_000_000)
        // Trong 2 giây dùng thêm 1 giây CPU trên máy 4 nhân → 12,5%.
        let r = ProcessTable.makeRow(current: now, previous: before, elapsedNs: 2_000_000_000, coreCount: 4, user: "me")
        XCTAssertEqual(r.cpuPercent, 12.5, accuracy: 0.001)
        XCTAssertEqual(r.diskReadPerSec, 1000, accuracy: 0.001)
        XCTAssertEqual(r.diskWritePerSec, 2000, accuracy: 0.001)
        // 2 J trong 2 s = 1 W = 1000 mW.
        XCTAssertEqual(r.powerMilliwatts, 1000, accuracy: 0.001)
        XCTAssertEqual(r.user, "me")
    }

    func testMakeRowClampsAndHandlesCounterReset() {
        let before = raw(cpuNs: 9_000_000_000, read: 9000)
        let now = raw(cpuNs: 1_000, read: 100) // bộ đếm lùi (tiến trình khởi động lại)
        let r = ProcessTable.makeRow(current: now, previous: before, elapsedNs: 1_000_000_000, coreCount: 2, user: "u")
        XCTAssertEqual(r.cpuPercent, 0)
        XCTAssertEqual(r.diskReadPerSec, 0)
        let burst = ProcessTable.makeRow(current: raw(cpuNs: 50_000_000_000), previous: raw(cpuNs: 0),
                                         elapsedNs: 1_000_000_000, coreCount: 1, user: "u")
        XCTAssertEqual(burst.cpuPercent, 100)
    }

    func testFirstUpdateHasNoRatesAndPidReuseIsIgnored() {
        let table = ProcessTable(coreCount: 1)
        let first = table.update(samples: [raw(cpuNs: 5_000_000_000, read: 5000)], nowNs: 1_000_000_000)
        XCTAssertEqual(first[0].cpuPercent, 0)
        XCTAssertEqual(first[0].diskReadPerSec, 0)
        // Cùng pid nhưng thời điểm khởi động khác = tiến trình mới: không được tính delta với tiến trình cũ.
        let reused = table.update(samples: [raw(start: 999, cpuNs: 6_000_000_000)], nowNs: 2_000_000_000)
        XCTAssertEqual(reused[0].cpuPercent, 0)
        let normal = table.update(samples: [raw(start: 999, cpuNs: 6_500_000_000)], nowNs: 3_000_000_000)
        XCTAssertEqual(normal[0].cpuPercent, 50, accuracy: 0.001)
    }

    func testMachTimeConversion() {
        XCTAssertEqual(ProcessSampler.machToNs(1_000, numer: 1, denom: 1), 1_000)
        XCTAssertEqual(ProcessSampler.machToNs(24_000_000, numer: 125, denom: 3), 1_000_000_000)
        // Giá trị lớn không được tràn: 10 năm ở 24 MHz.
        let ticks: UInt64 = 24_000_000 * 86_400 * 3650
        XCTAssertEqual(ProcessSampler.machToNs(ticks, numer: 125, denom: 3), 86_400 * 3650 * 1_000_000_000)
    }

    // MARK: Gom nhóm, lọc, sắp xếp

    func testAppBundlePathGroupsHelpersUnderOuterApp() {
        let helper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
        XCTAssertEqual(ProcessGrouping.appBundlePath(forExecutable: helper), "/Applications/Google Chrome.app")
        XCTAssertEqual(ProcessGrouping.appBundlePath(forExecutable: "/Applications/Safari.app/Contents/MacOS/Safari"), "/Applications/Safari.app")
        XCTAssertNil(ProcessGrouping.appBundlePath(forExecutable: "/usr/sbin/cfprefsd"))
        XCTAssertNil(ProcessGrouping.appBundlePath(forExecutable: ""))
        XCTAssertEqual(ProcessGrouping.appName(forBundlePath: "/Applications/Google Chrome.app"), "Google Chrome")
    }

    func testGroupingSumsAndKeepsBackgroundSeparate() {
        let rows = [
            row(pid: 10, name: "Chrome", path: "/Applications/Google Chrome.app/Contents/MacOS/Chrome", cpu: 10, mem: 100),
            row(pid: 11, name: "Chrome Helper", path: "/Applications/Google Chrome.app/Contents/Frameworks/H.app/Contents/MacOS/H", cpu: 5, mem: 300),
            row(pid: 20, name: "cfprefsd", path: "/usr/sbin/cfprefsd", cpu: 1, mem: 50),
        ]
        let groups = ProcessGrouping.group(rows)
        XCTAssertEqual(groups.count, 2)
        let chrome = groups.first { $0.isApp }
        XCTAssertEqual(chrome?.name, "Google Chrome")
        XCTAssertEqual(chrome?.rows.count, 2)
        XCTAssertEqual(chrome?.memoryBytes, 400)
        XCTAssertEqual(chrome?.cpuPercent ?? 0, 15, accuracy: 0.001)
        XCTAssertFalse(groups.first { !$0.isApp }!.isApp)
    }

    func testUserAppsAreDecidedByActivationPolicyWhenProvided() {
        let rows = [
            row(pid: 10, name: "Safari", path: "/Applications/Safari.app/Contents/MacOS/Safari"),
            row(pid: 11, name: "loginwindow", path: "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow"),
            row(pid: 12, name: "Safari Web", path: "/Applications/Safari.app/Contents/XPCServices/W.xpc/Contents/MacOS/W"),
        ]
        let groups = ProcessGrouping.group(rows, userAppPIDs: [10])
        XCTAssertEqual(groups.first { $0.name == "Safari" }?.isApp, true)
        XCTAssertEqual(groups.first { $0.name == "Safari" }?.rows.count, 2)
        XCTAssertEqual(groups.first { $0.name == "loginwindow" }?.isApp, false)
        // Không có thông tin activation policy thì rơi về quy tắc đường dẫn .app.
        XCTAssertEqual(ProcessGrouping.group(rows).filter(\.isApp).count, 2)
    }

    func testFilterMatchesNamePidAndPath() {
        let groups = ProcessGrouping.group([
            row(pid: 10, name: "Safari", path: "/Applications/Safari.app/Contents/MacOS/Safari"),
            row(pid: 20, name: "cfprefsd", path: "/usr/sbin/cfprefsd"),
        ])
        XCTAssertEqual(ProcessGrouping.filter(groups, query: "safa").count, 1)
        XCTAssertEqual(ProcessGrouping.filter(groups, query: "20").first?.name, "cfprefsd")
        XCTAssertEqual(ProcessGrouping.filter(groups, query: "/usr/sbin").count, 1)
        XCTAssertEqual(ProcessGrouping.filter(groups, query: "  ").count, 2)
        XCTAssertTrue(ProcessGrouping.filter(groups, query: "zzz").isEmpty)
    }

    func testSortByCPUAndNameBothDirections() {
        let groups = ProcessGrouping.group([
            row(pid: 1, name: "b", cpu: 5), row(pid: 2, name: "A", cpu: 50), row(pid: 3, name: "c", cpu: 1),
        ])
        XCTAssertEqual(ProcessGrouping.sort(groups, by: .cpu, ascending: false).map(\.name), ["A", "b", "c"])
        XCTAssertEqual(ProcessGrouping.sort(groups, by: .cpu, ascending: true).map(\.name), ["c", "b", "A"])
        XCTAssertEqual(ProcessGrouping.sort(groups, by: .name, ascending: true).map(\.name), ["A", "b", "c"])
    }

    // MARK: An toàn

    func testSafetyVerdicts() {
        XCTAssertEqual(ProcessSafety.verdict(for: row(pid: 1, name: "launchd", uid: 0), selfPID: 500, currentUID: 501), .protectedSystem)
        XCTAssertEqual(ProcessSafety.verdict(for: row(pid: 77, name: "WindowServer", uid: 88), selfPID: 500, currentUID: 501), .protectedSystem)
        XCTAssertEqual(ProcessSafety.verdict(for: row(pid: 500, name: "MacHub"), selfPID: 500, currentUID: 501), .itself)
        XCTAssertEqual(ProcessSafety.verdict(for: row(pid: 300, name: "mdworker", uid: 0), selfPID: 500, currentUID: 501), .needsAdmin)
        XCTAssertEqual(ProcessSafety.verdict(for: row(pid: 301, name: "Safari", uid: 501), selfPID: 500, currentUID: 501), .allowed)
    }

    // MARK: Hành động trên tiến trình thật (tiến trình con do test tự tạo)

    @MainActor private func spawnSleeper() throws -> (Process, ProcessRow) {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["600"]
        try child.run()
        let sample = try XCTUnwrap(ProcessSampler.read(pid: child.processIdentifier))
        let row = ProcessTable.makeRow(current: sample, previous: nil, elapsedNs: 0, coreCount: 1, user: "u")
        return (child, row)
    }

    @MainActor private func waitUntilExit(_ child: Process) async {
        for _ in 0..<40 where child.isRunning { try? await Task.sleep(nanoseconds: 100_000_000) }
    }

    @MainActor func testEndTaskSendsSIGTERM() async throws {
        let (child, row) = try spawnSleeper()
        defer { if child.isRunning { child.terminate() } }
        XCTAssertEqual(ProcessSafety.verdict(for: row), .allowed)
        TaskManagerModel.shared.endTask([row])
        await waitUntilExit(child)
        XCTAssertFalse(child.isRunning)
        XCTAssertEqual(child.terminationReason, .uncaughtSignal)
        XCTAssertEqual(child.terminationStatus, SIGTERM)
    }

    @MainActor func testForceKillSendsSIGKILL() async throws {
        let (child, row) = try spawnSleeper()
        defer { if child.isRunning { child.terminate() } }
        TaskManagerModel.shared.forceKill([row])
        await waitUntilExit(child)
        XCTAssertEqual(child.terminationStatus, SIGKILL)
    }

    @MainActor func testSuspendAndResume() async throws {
        let (child, row) = try spawnSleeper()
        defer { if child.isRunning { child.terminate() } }
        TaskManagerModel.shared.suspend([row])
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(ProcessSampler.read(pid: row.pid)?.isStopped, true)
        TaskManagerModel.shared.resume([row])
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(ProcessSampler.read(pid: row.pid)?.isStopped, false)
    }

    @MainActor func testSetNiceLowersPriority() async throws {
        let (child, row) = try spawnSleeper()
        defer { if child.isRunning { child.terminate() } }
        TaskManagerModel.shared.setNice(10, for: [row])
        XCTAssertEqual(ProcessSampler.read(pid: row.pid)?.nice, 10)
    }

    @MainActor func testProtectedAndForeignProcessesAreNeverSignalled() throws {
        let model = TaskManagerModel.shared
        let launchd = try XCTUnwrap(ProcessSampler.read(pid: 1))
        let row = ProcessTable.makeRow(current: launchd, previous: nil, elapsedNs: 0, coreCount: 1, user: "root")
        model.endTask([row])
        XCTAssertTrue(model.message?.contains("launchd") == true, "phải báo launchd được bảo vệ")
        model.forceKill([row])
        // Chính MacHub cũng không được tự kết thúc.
        let me = try XCTUnwrap(ProcessSampler.read(pid: getpid()))
        let selfRow = ProcessTable.makeRow(current: me, previous: nil, elapsedNs: 0, coreCount: 1, user: "me")
        model.endTask([selfRow])
        XCTAssertNotNil(model.message)
        XCTAssertEqual(kill(getpid(), 0), 0, "test runner vẫn còn sống")
    }

    // MARK: Hệ thống

    func testSystemSamplerProducesSaneNumbers() {
        let s = SystemSampler()
        _ = s.sample(nowNs: 1_000_000_000, processCount: 1, threadCount: 1)
        Thread.sleep(forTimeInterval: 0.4)
        let snap = s.sample(nowNs: 1_400_000_000, processCount: 5, threadCount: 9)
        XCTAssertEqual(snap.perCorePercent.count, ProcessInfo.processInfo.activeProcessorCount)
        XCTAssertTrue((0...100).contains(snap.cpuPercent))
        XCTAssertEqual(snap.memoryTotal, ProcessInfo.processInfo.physicalMemory)
        XCTAssertGreaterThan(snap.memoryUsed, 0)
        XCTAssertLessThanOrEqual(snap.memoryUsed, snap.memoryTotal)
        XCTAssertTrue((0...100).contains(snap.memoryPercent))
        XCTAssertGreaterThanOrEqual(snap.diskReadPerSec, 0)
        XCTAssertGreaterThanOrEqual(snap.netDownPerSec, 0)
        XCTAssertEqual(snap.processCount, 5)
    }

    func testHistoryKeepsLatestValuesOnly() {
        var h = History(capacity: 3)
        for v in 1...5 { h.append(Double(v)) }
        XCTAssertEqual(h.values, [3, 4, 5])
        XCTAssertEqual(h.peak(floor: 10), 10)
        XCTAssertEqual(h.peak(floor: 1), 5)
    }

    func testFormatting() {
        XCTAssertEqual(TaskManagerFormat.bytes(512), "512 B")
        XCTAssertEqual(TaskManagerFormat.bytes(1536), "1.5 KB")
        XCTAssertEqual(TaskManagerFormat.bytes(5 * 1024 * 1024 * 1024), "5.0 GB")
        XCTAssertEqual(TaskManagerFormat.rate(0), "0 B/s")
        XCTAssertEqual(TaskManagerFormat.rate(2048), "2.0 KB/s")
        XCTAssertEqual(TaskManagerFormat.percent(0), "0%")
        XCTAssertEqual(TaskManagerFormat.percent(3.14), "3.1%")
        XCTAssertEqual(TaskManagerFormat.percent(42.6), "43%")
        XCTAssertEqual(TaskManagerFormat.power(1500), "1.5 W")
        XCTAssertEqual(TaskManagerFormat.uptime(90_061), "1:01:01")
    }

    // MARK: Phím tắt

    func testTaskManagerShortcutDefault() {
        let config = ShortcutConfiguration()
        XCTAssertEqual(config.match(53, flags: [.maskControl, .maskShift])?.action, .taskManager)
        XCTAssertNil(config.match(53, flags: .maskControl))
        XCTAssertNil(ShortcutConfiguration.invalidReason(ShortcutAction.taskManager.defaults[0], action: .taskManager))
        // Không trùng phím mặc định nào khác.
        for other in ShortcutAction.allCases where other != .taskManager {
            XCTAssertFalse(other.defaults.contains(ShortcutAction.taskManager.defaults[0]), "trùng với \(other)")
        }
    }
}

private extension ProcessRow {
    func with(cpu: Double) -> ProcessRow { var copy = self; copy.cpuPercent = cpu; return copy }
}
