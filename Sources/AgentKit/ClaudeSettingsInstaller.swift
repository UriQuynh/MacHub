// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import Foundation

/// Thêm / gỡ hook của MacHub trong `~/.claude/settings.json`.
///
/// Nguyên tắc:
/// - Chỉ đụng tới mục của MacHub (nhận diện bằng lệnh chứa `machub-agent-hook`); giữ nguyên mọi cấu hình khác.
/// - File không phải JSON hợp lệ → từ chối, không ghi đè.
/// - Luôn sao lưu bản cũ trước khi ghi (`settings.json.machub-backup-<thời điểm>`).
/// - statusLine cũ của người dùng được lưu lại để hook chạy tiếp và để khôi phục khi gỡ.
public struct ClaudeSettingsInstaller {
    public static let marker = "machub-agent-hook"

    /// Sự kiện chỉ để quan sát → chạy nền (`async`), không làm chậm Claude Code.
    public static let observedEvents = [
        "SessionStart", "SessionEnd", "UserPromptSubmit", "Stop",
        "SubagentStart", "SubagentStop", "Notification",
    ]

    public struct Options: Equatable, Sendable {
        public var observe = true
        /// Hook `PermissionRequest` để duyệt quyền từ MacHub (đồng bộ: Claude chờ quyết định).
        public var approvals = true
        /// Thay statusLine bằng lệnh của MacHub (vẫn chạy statusLine cũ của bạn bên trong).
        public var statusLine = true
        /// Thời gian tối đa Claude Code chờ hook PermissionRequest (giây). App tự trả lời sớm hơn.
        public var approvalHookTimeout = 600

        public init(observe: Bool = true, approvals: Bool = true, statusLine: Bool = true) {
            self.observe = observe
            self.approvals = approvals
            self.statusLine = statusLine
        }
    }

    public struct State: Equatable, Sendable {
        public var observe = false
        public var approvals = false
        public var statusLine = false
        public var installed: Bool { observe || approvals || statusLine }

        public init(observe: Bool = false, approvals: Bool = false, statusLine: Bool = false) {
            self.observe = observe
            self.approvals = approvals
            self.statusLine = statusLine
        }
    }

    public enum InstallError: Error, CustomStringConvertible {
        case invalidJSON
        case notAnObject
        public var description: String {
            switch self {
            case .invalidJSON: return "~/.claude/settings.json không phải JSON hợp lệ — MacHub không sửa để tránh làm hỏng cấu hình."
            case .notAnObject: return "~/.claude/settings.json phải là một object JSON."
            }
        }
    }

    public let hookPath: String

    public init(hookPath: String) {
        self.hookPath = hookPath
    }

    func command(_ mode: String) -> String {
        "\"\(hookPath)\" \(mode)"
    }

    static func isOurs(_ handler: Any) -> Bool {
        ((handler as? [String: Any])?["command"] as? String)?.contains(marker) == true
    }

    // MARK: - Đọc trạng thái

    public static func state(of settings: [String: Any]) -> State {
        var s = State()
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, groups) in hooks {
            let ours = (groups as? [Any] ?? []).contains { group in
                ((group as? [String: Any])?["hooks"] as? [Any] ?? []).contains(where: isOurs)
            }
            guard ours else { continue }
            if event == "PermissionRequest" { s.approvals = true } else { s.observe = true }
        }
        if isOurs(settings["statusLine"] as Any) { s.statusLine = true }
        return s
    }

    // MARK: - Biến đổi (thuần, dễ kiểm thử)

    /// Bỏ mọi hook của MacHub; xóa nhóm/sự kiện rỗng do việc bỏ này tạo ra.
    public static func removingOurHooks(from settings: [String: Any]) -> [String: Any] {
        var out = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return out }
        for (event, value) in hooks {
            guard let groups = value as? [Any] else { continue }
            var newGroups: [Any] = []
            for group in groups {
                guard var g = group as? [String: Any], let handlers = g["hooks"] as? [Any] else {
                    newGroups.append(group)
                    continue
                }
                let kept = handlers.filter { !isOurs($0) }
                if kept.count == handlers.count {
                    newGroups.append(group)
                } else if !kept.isEmpty {
                    g["hooks"] = kept
                    newGroups.append(g)
                }
            }
            if newGroups.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = newGroups }
        }
        if hooks.isEmpty { out.removeValue(forKey: "hooks") } else { out["hooks"] = hooks }
        return out
    }

    /// Trả về settings mới + statusLine cũ cần lưu lại (nếu có).
    public func installing(into settings: [String: Any], options: Options) -> (settings: [String: Any], previousStatusLine: [String: Any]?) {
        var out = Self.removingOurHooks(from: settings)
        var hooks = out["hooks"] as? [String: Any] ?? [:]

        if options.observe {
            for event in Self.observedEvents {
                var groups = hooks[event] as? [Any] ?? []
                groups.append(["hooks": [["type": "command", "command": command("claude"), "timeout": 10, "async": true]]])
                hooks[event] = groups
            }
        }
        if options.approvals {
            var groups = hooks["PermissionRequest"] as? [Any] ?? []
            groups.append(["hooks": [["type": "command", "command": command("claude"), "timeout": options.approvalHookTimeout]]])
            hooks["PermissionRequest"] = groups
        }
        if !hooks.isEmpty { out["hooks"] = hooks }

        var previous: [String: Any]?
        let current = out["statusLine"] as? [String: Any]
        if options.statusLine {
            if let current, !Self.isOurs(current) { previous = current }
            var line: [String: Any] = ["type": "command", "command": command("statusline")]
            if let padding = current?["padding"] { line["padding"] = padding }
            out["statusLine"] = line
        }
        return (out, previous)
    }

    /// Gỡ toàn bộ: bỏ hook của MacHub và trả lại statusLine cũ (hoặc xóa nếu trước đó không có).
    public static func uninstalling(from settings: [String: Any], previousStatusLine: [String: Any]?) -> [String: Any] {
        var out = removingOurHooks(from: settings)
        if isOurs(out["statusLine"] as Any) {
            if let previousStatusLine { out["statusLine"] = previousStatusLine } else { out.removeValue(forKey: "statusLine") }
        }
        return out
    }

    // MARK: - Đọc/ghi file

    public static func load(_ url: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { throw InstallError.invalidJSON }
        guard let dict = obj as? [String: Any] else { throw InstallError.notAnObject }
        return dict
    }

    /// Ghi atomic, sao lưu bản cũ, giữ quyền file cũ. Trả về đường dẫn bản sao lưu (nếu có).
    @discardableResult
    public static func save(_ settings: [String: Any], to url: URL, now: Date = Date()) throws -> URL? {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var backup: URL?
        var perms: Any?
        if fm.fileExists(atPath: url.path) {
            perms = (try? fm.attributesOfItem(atPath: url.path))?[.posixPermissions]
            let stamp = Int(now.timeIntervalSince1970)
            let b = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).machub-backup-\(stamp)")
            try? fm.removeItem(at: b)
            try fm.copyItem(at: url, to: b)
            backup = b
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
        if let perms { try? fm.setAttributes([.posixPermissions: perms], ofItemAtPath: url.path) }
        return backup
    }
}

/// Cấu hình phía hook (`agent-hook.json`): statusLine cũ của người dùng và thời gian chờ duyệt.
public struct AgentHookConfig: Codable, Equatable, Sendable {
    public var previousStatusLineCommand: String?
    public var previousStatusLine: JSONValue?
    /// Giây hook chờ MacHub trả lời yêu cầu quyền trước khi để terminal tự hỏi.
    public var approvalTimeoutSeconds: Double

    public init(previousStatusLine: JSONValue? = nil, approvalTimeoutSeconds: Double = 120) {
        self.previousStatusLine = previousStatusLine
        self.previousStatusLineCommand = previousStatusLine?["command"]?.string
        self.approvalTimeoutSeconds = approvalTimeoutSeconds
    }

    public static func load(_ url: URL = AgentPaths.hookConfigURL) -> AgentHookConfig {
        guard let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(AgentHookConfig.self, from: data) else { return AgentHookConfig() }
        return cfg
    }

    public func save(_ url: URL = AgentPaths.hookConfigURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
