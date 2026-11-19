// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import AgentKit
import Foundation

/// Cài / gỡ hook MacHub cho Claude Code (chỉ khi người dùng bấm nút).
enum AgentHookSetup {
    enum SetupError: Error {
        case missingBundledHook
        case settings(String)

        var message: String {
            switch self {
            case .missingBundledHook: return tr("Không tìm thấy machub-agent-hook trong MacHub.app.", "machub-agent-hook is missing from MacHub.app.")
            case .settings(let m): return m
            }
        }
    }

    static var bundledHook: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/machub-agent-hook")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// Chép hook ra vị trí cố định (không đổi khi MacHub.app bị di chuyển / cập nhật).
    static func refreshHookBinary() throws {
        guard let src = bundledHook else { throw SetupError.missingBundledHook }
        let dst = AgentPaths.hookBinaryURL
        let fm = FileManager.default
        try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let tmp = dst.deletingLastPathComponent().appendingPathComponent(".machub-agent-hook.tmp")
        try? fm.removeItem(at: tmp)
        try fm.copyItem(at: src, to: tmp)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        if fm.fileExists(atPath: dst.path) {
            _ = try fm.replaceItemAt(dst, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: dst)
        }
    }

    static func currentState() -> ClaudeSettingsInstaller.State {
        guard let settings = try? ClaudeSettingsInstaller.load(AgentPaths.claudeSettingsURL) else { return .init() }
        return ClaudeSettingsInstaller.state(of: settings)
    }

    /// Cài theo tùy chọn. Trả về đường dẫn bản sao lưu settings.json (nếu có).
    @discardableResult
    static func install(options: ClaudeSettingsInstaller.Options, approvalTimeout: Double) throws -> URL? {
        try refreshHookBinary()
        let url = AgentPaths.claudeSettingsURL
        let settings: [String: Any]
        do { settings = try ClaudeSettingsInstaller.load(url) } catch { throw SetupError.settings(String(describing: error)) }

        let installer = ClaudeSettingsInstaller(hookPath: AgentPaths.hookBinaryURL.path)
        let (updated, previous) = installer.installing(into: settings, options: options)

        var cfg = AgentHookConfig.load()
        if let previous, let data = try? JSONSerialization.data(withJSONObject: previous), let json = JSONValue.parse(data) {
            cfg = AgentHookConfig(previousStatusLine: json, approvalTimeoutSeconds: approvalTimeout)
        } else {
            cfg.approvalTimeoutSeconds = approvalTimeout
        }
        try cfg.save()
        return try ClaudeSettingsInstaller.save(updated, to: url)
    }

    @discardableResult
    static func uninstall() throws -> URL? {
        let url = AgentPaths.claudeSettingsURL
        let settings: [String: Any]
        do { settings = try ClaudeSettingsInstaller.load(url) } catch { throw SetupError.settings(String(describing: error)) }
        let cfg = AgentHookConfig.load()
        var previous: [String: Any]?
        if let prev = cfg.previousStatusLine,
           let obj = try? JSONSerialization.jsonObject(with: prev.encoded()) as? [String: Any] {
            previous = obj
        }
        let updated = ClaudeSettingsInstaller.uninstalling(from: settings, previousStatusLine: previous)
        let backup = try ClaudeSettingsInstaller.save(updated, to: url)
        try? AgentHookConfig(previousStatusLine: nil, approvalTimeoutSeconds: cfg.approvalTimeoutSeconds).save()
        return backup
    }
}
