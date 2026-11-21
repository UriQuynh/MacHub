// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import AppKit
import SwiftUI

/// Cửa sổ Task Manager riêng (popover của menu bar quá nhỏ cho bảng tiến trình).
/// Chỉ lấy mẫu khi cửa sổ đang mở.
@MainActor
final class TaskManagerWindowController: NSObject, NSWindowDelegate {
    static let shared = TaskManagerWindowController()

    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible == true }

    func toggle() {
        if isVisible, window?.isKeyWindow == true { window?.performClose(nil) } else { show() }
    }

    func show() {
        if window == nil { window = makeWindow() }
        guard let window else { return }
        TaskManagerModel.shared.start()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = tr("Trình quản lý tác vụ", "Task Manager")
        window.contentView = NSHostingView(rootView: TaskManagerView(model: TaskManagerModel.shared))
        window.minSize = NSSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("MacHubTaskManager")
        window.delegate = self
        if !window.setFrameUsingName("MacHubTaskManager") { window.center() }
        return window
    }

    func windowWillClose(_ notification: Notification) {
        TaskManagerModel.shared.stop()
    }

    func windowDidMiniaturize(_ notification: Notification) {
        TaskManagerModel.shared.stop()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        TaskManagerModel.shared.start()
    }
}
