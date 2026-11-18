// SPDX-License-Identifier: GPL-3.0-only
// MacHub — fork of HyperMac. Original work Copyright (C) 2026 Nguyễn Khắc Đại.
// Modifications Copyright (C) 2026 MacHub contributors.

import AppKit
import Combine
import Foundation
import Sparkle

/// Cập nhật tự động qua Sparkle.
///
/// Thay cho bộ cập nhật tự viết của HyperMac (tải zip rồi chỉ kiểm tra bundle ID, chạy script
/// trong `/tmp` và `xattr -cr`). Sparkle chỉ cài gói khi:
/// 1. Chữ ký EdDSA của file zip khớp `SUPublicEDKey` trong Info.plist, và
/// 2. Chữ ký code của app mới khớp chứng chỉ đang ký app hiện tại.
/// Feed (`SUFeedURL`) và khóa công khai được `build.sh` ghi vào Info.plist từ `config/`.
@MainActor
public final class UpdateManager: NSObject, ObservableObject {
    public static let shared = UpdateManager()

    /// Phiên bản đang chạy (CFBundleShortVersionString do build.sh ghi từ file VERSION).
    nonisolated public static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Tắt cập nhật khi bản build chưa cấu hình khóa/feed (vd. build local chưa chạy setup-sparkle-keys.sh)
    /// hoặc khi chạy trực tiếp binary ngoài .app bundle (swift run / test).
    nonisolated public static var updatesDisabled: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        guard Bundle.main.bundleURL.pathExtension == "app",
              let key = info["SUPublicEDKey"] as? String, !key.isEmpty, !key.hasPrefix("__"),
              let feed = info["SUFeedURL"] as? String, feed.hasPrefix("https://"), !feed.contains("__")
        else { return true }
        return false
    }

    /// Trang mã nguồn / releases của MacHub.
    nonisolated public static var repositoryURL: URL? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "MHRepositoryURL") as? String,
              !s.contains("__") else { return nil }
        return URL(string: s)
    }

    @Published public private(set) var hasNewUpdate: Bool = false
    @Published public private(set) var latestVersionString: String = ""

    private var controller: SPUStandardUpdaterController?

    override private init() {
        super.init()
        guard !Self.updatesDisabled else {
            appLog("ℹ️ UpdateManager: tự cập nhật bị tắt (chưa cấu hình SUPublicEDKey/SUFeedURL).")
            return
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }

    /// Bật/tắt kiểm tra định kỳ (Sparkle tự lưu lựa chọn này).
    public var autoCheckEnabled: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    /// `silent = true`: kiểm tra nền, chỉ hiện UI khi có bản mới.
    /// `silent = false`: người dùng bấm "Cập nhật" → luôn hiện kết quả.
    public func checkForUpdates(silent: Bool = false) {
        guard let controller else {
            if !silent, let url = Self.repositoryURL?.appendingPathComponent("releases") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        if silent {
            controller.updater.checkForUpdatesInBackground()
        } else {
            // App chạy ẩn Dock (LSUIElement): phải activate thì cửa sổ Sparkle mới lên trước.
            NSApp.activate(ignoringOtherApps: true)
            controller.checkForUpdates(nil)
        }
    }

    public func openReleasePage() {
        if let url = Self.repositoryURL?.appendingPathComponent("releases") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateManager: SPUUpdaterDelegate {
    public func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        hasNewUpdate = true
        latestVersionString = item.displayVersionString
        appLog("✨ UpdateManager: có bản mới \(item.displayVersionString) (hiện tại \(Self.currentVersion))")
    }

    public func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        hasNewUpdate = false
    }

    public func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        appLog("⚠️ UpdateManager: \(error.localizedDescription)")
    }
}

// MARK: - SPUStandardUserDriverDelegate

// Protocol này không được Sparkle đánh dấu UI actor, nhưng Sparkle luôn gọi trên main thread,
// nên các member là `nonisolated` và vào lại MainActor bằng `assumeIsolated`.
extension UpdateManager: SPUStandardUserDriverDelegate {
    /// App menu bar không có cửa sổ chính: dùng "gentle reminders" để Sparkle không bật
    /// hộp thoại đè lên việc người dùng đang làm; thay vào đó nút Cập nhật ở footer sáng lên.
    nonisolated public var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated public func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    nonisolated public func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        let version = update.displayVersionString
        MainActor.assumeIsolated {
            self.hasNewUpdate = true
            self.latestVersionString = version
        }
    }
}
