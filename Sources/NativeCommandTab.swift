// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import Foundation
import AppKit

/// Tắt bộ chuyển ứng dụng gốc của macOS (⌘Tab, ⌘⇧Tab) khi MacHub đang dùng ⌘Tab cho Alt-Tab của riêng nó.
///
/// Vì sao cần: ⌘Tab là "symbolic hotkey" do WindowServer/Dock xử lý TRƯỚC khi sự kiện tới event tap của app,
/// nên MacHub không chặn được nó chỉ bằng `CGEventTap`: bấm ⌘Tab thật vẫn ra bộ chuyển ứng dụng gốc (⌥Tab
/// thì chạy vì macOS không dùng tổ hợp này). Các app thay Alt-Tab (như alt-tab-macos) cũng phải tắt phím tắt gốc
/// bằng API riêng của SkyLight `CGSSetSymbolicHotKeyEnabled`.
///
/// An toàn: chỉ tắt khi bộ bắt phím của MacHub đang chạy; luôn bật lại khi tắt Alt-Tab, đổi phím, dừng bộ bắt phím,
/// thoát app, hoặc nhận SIGTERM/SIGINT/SIGHUP. Nếu app bị kill -9/crash thì ⌘Tab gốc tắt tới khi mở lại MacHub
/// hoặc đăng xuất (trạng thái này nằm trong phiên WindowServer, không ghi vào cấu hình).
@MainActor
enum NativeCommandTab {
    /// Mã symbolic hotkey: 1 = ⌘Tab, 2 = ⌘⇧Tab.
    static let hotKeys: [Int32] = [1, 2]

    private typealias SetFn = @convention(c) (Int32, Bool) -> Int32
    private typealias GetFn = @convention(c) (Int32) -> Bool

    private static let setFn: SetFn? = {
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "CGSSetSymbolicHotKeyEnabled") else { return nil }
        return unsafeBitCast(sym, to: SetFn.self)
    }()
    private static let getFn: GetFn? = {
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "CGSIsSymbolicHotKeyEnabled") else { return nil }
        return unsafeBitCast(sym, to: GetFn.self)
    }()

    /// true khi chính MacHub đã tắt ⌘Tab gốc (để chỉ bật lại phần mình đã tắt).
    private(set) static var isOverriding = false
    private static var observers: [NSObjectProtocol] = []
    private static var signalSources: [DispatchSourceSignal] = []

    /// Thuần hàm để kiểm thử: có nên tắt ⌘Tab gốc với cấu hình này không.
    static func shouldOverride(configuration: ShortcutConfiguration, altTabEnabled: Bool, tapActive: Bool) -> Bool {
        guard altTabEnabled, tapActive else { return false }
        let tabKey: UInt16 = 48
        return (configuration.bindings[.switchWindows] ?? []).contains {
            $0.keyCode == tabKey && $0.flags == .maskCommand
        }
    }

    /// Hiện trạng ⌘Tab gốc của hệ thống (nil nếu không đọc được API).
    static var nativeIsEnabled: Bool? { getFn?(hotKeys[0]) }

    /// Cập nhật theo cấu hình hiện tại. Gọi lại bao nhiêu lần cũng được.
    static func refresh() {
        installObserversIfNeeded()
        let want = shouldOverride(configuration: gShortcutConfiguration,
                                  altTabEnabled: gIsAltTabEnabled,
                                  tapActive: KeyInterceptor.shared.currentTap != nil)
        apply(override: want)
    }

    /// Trả ⌘Tab gốc về như cũ (nếu MacHub đã tắt nó).
    static func restore() {
        apply(override: false)
    }

    private static func apply(override want: Bool) {
        guard want != isOverriding else { return }
        guard let setFn else {
            appLog("⚠️ NativeCommandTab: không có CGSSetSymbolicHotKeyEnabled, ⌘Tab gốc giữ nguyên")
            return
        }
        for key in hotKeys { _ = setFn(key, !want) }
        isOverriding = want
        appLog(want ? "⌨️ Đã tắt ⌘Tab gốc của macOS, MacHub xử lý ⌘Tab" : "⌨️ Đã bật lại ⌘Tab gốc của macOS")
    }

    private static func installObserversIfNeeded() {
        guard observers.isEmpty else { return }
        observers.append(NotificationCenter.default.addObserver(
            forName: .machubShortcutsChanged, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { NativeCommandTab.refresh() } })

        // Dừng giữa chừng (kill nhẹ) cũng phải trả ⌘Tab gốc.
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { NativeCommandTab.restore() }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
