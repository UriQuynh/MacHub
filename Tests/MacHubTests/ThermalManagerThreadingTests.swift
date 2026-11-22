// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import XCTest
import Combine
@testable import MacHub

/// Tái hiện lỗi treo cứng MacHub: `ProcessInfo.thermalStateDidChangeNotification` được post từ luồng nền,
/// handler cũ chạy `refreshMetrics()` (ghi nhiều thuộc tính `@Published`) ngay trên luồng nền đó, đồng thời
/// với luồng chính → kẹt khoá của Combine, luồng chính đứng yên vĩnh viễn.
final class ThermalManagerThreadingTests: XCTestCase {
    @MainActor func testThermalNotificationStormFromBackgroundThreadsDoesNotWedgeMainThread() async throws {
        let manager = ThermalManager.shared
        var cancellables = Set<AnyCancellable>()
        // Có subscriber thật (như SwiftUI) để mỗi lần ghi @Published đi qua đường publish.
        manager.objectWillChange.sink { _ in }.store(in: &cancellables)

        // Nếu bị kẹt khoá, dừng cả tiến trình test thay vì treo CI hàng giờ.
        let watchdog = DispatchWorkItem { fatalError("ThermalManager: luồng chính bị kẹt khoá Combine (deadlock)") }
        DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: watchdog)
        defer { watchdog.cancel() }

        let group = DispatchGroup()
        for _ in 0..<48 {
            group.enter()
            DispatchQueue.global(qos: .userInteractive).async {
                for _ in 0..<25 {
                    NotificationCenter.default.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
                }
                group.leave()
            }
        }

        // Trong lúc đó luồng chính vẫn làm việc như timer thật (đọc nhiệt độ và ghi @Published).
        let end = Date().addingTimeInterval(6)
        var refreshes = 0
        while Date() < end {
            manager.refreshMetrics()
            refreshes += 1
            try await Task.sleep(nanoseconds: 15_000_000)
        }
        XCTAssertGreaterThan(refreshes, 10, "luồng chính phải còn chạy được")
        XCTAssertEqual(group.wait(timeout: .now() + 20), .success)
        // Cho các cập nhật đã gom về luồng chính được xử lý xong.
        try await Task.sleep(nanoseconds: 500_000_000)
    }

    /// Handler phải đưa việc về luồng chính và gộp các thông báo dồn dập thành ít lần đọc.
    @MainActor func testBurstOfNotificationsIsCoalesced() async throws {
        let manager = ThermalManager.shared
        let before = manager.thermalStateRefreshCount
        for _ in 0..<200 {
            NotificationCenter.default.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        }
        try await Task.sleep(nanoseconds: 800_000_000)
        let handled = manager.thermalStateRefreshCount - before
        XCTAssertGreaterThanOrEqual(handled, 1, "phải có ít nhất một lần cập nhật")
        XCTAssertLessThan(handled, 20, "200 thông báo dồn dập không được gây 200 lần đọc cảm biến")
    }
}
