// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import Foundation

/// Đường dẫn dùng chung giữa app MacHub và `machub-agent-hook`.
public enum AgentPaths {
    public static var supportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["MACHUB_AGENT_SUPPORT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacHub", isDirectory: true)
    }

    /// Socket Unix (quyền 0600, trong thư mục 0700) mà hook gửi sự kiện tới.
    public static var socketURL: URL { supportDirectory.appendingPathComponent("agent.sock") }

    /// Bản sao ổn định của hook (không phụ thuộc vị trí MacHub.app).
    public static var hookBinaryURL: URL {
        supportDirectory.appendingPathComponent("bin", isDirectory: true).appendingPathComponent("machub-agent-hook")
    }

    /// Cấu hình phía hook: lệnh statusLine cũ của người dùng (để chạy tiếp và khôi phục khi gỡ).
    public static var hookConfigURL: URL { supportDirectory.appendingPathComponent("agent-hook.json") }

    public static var claudeConfigDirectory: URL {
        if let dir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }

    public static var claudeSettingsURL: URL { claudeConfigDirectory.appendingPathComponent("settings.json") }

    /// Nơi Claude Code lưu transcript. Bản mới có thể dùng `~/.config/claude`.
    public static var claudeProjectDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            claudeConfigDirectory.appendingPathComponent("projects", isDirectory: true),
            home.appendingPathComponent(".config/claude/projects", isDirectory: true),
        ]
    }

    public static var codexSessionsDirectory: URL {
        if let dir = ProcessInfo.processInfo.environment["CODEX_HOME"], !dir.isEmpty {
            return URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions", isDirectory: true)
    }
}

/// Gói tin hook → app (một dòng JSON).
public struct AgentEnvelope: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case claudeHook = "claude-hook"
        case claudeStatusLine = "claude-statusline"
    }

    public var version: Int
    public var kind: Kind
    public var payload: JSONValue
    public var wantsReply: Bool
    public var sentAt: Date
    /// PID của tiến trình đã gọi hook (thường là Claude Code), để biết phiên còn sống.
    public var parentPID: Int32

    public init(kind: Kind, payload: JSONValue, wantsReply: Bool, sentAt: Date = Date(), parentPID: Int32 = getppid()) {
        self.version = 1
        self.kind = kind
        self.payload = payload
        self.wantsReply = wantsReply
        self.sentAt = sentAt
        self.parentPID = parentPID
    }
}

/// Trả lời app → hook. `output` là JSON hook in ra stdout cho Claude Code; `nil` = không quyết định.
public struct AgentReply: Codable, Equatable, Sendable {
    public var output: JSONValue?
    public init(output: JSONValue?) { self.output = output }
}

public enum AgentCoding {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }
}

/// Quyết định cho một yêu cầu quyền (PermissionRequest) của Claude Code.
public enum PermissionDecision: Equatable, Sendable {
    case allow
    /// Cho phép và áp dụng các quy tắc Claude Code gợi ý (`permission_suggestions`), vd. "luôn cho phép lệnh này".
    case allowAlways(suggestions: JSONValue)
    case deny(message: String)
    /// Không quyết định: Claude Code tự hỏi trong terminal như bình thường.
    case askInTerminal

    /// JSON hook in ra stdout. `nil` = không in gì.
    public var hookOutput: JSONValue? {
        let decision: JSONValue
        switch self {
        case .allow:
            decision = ["behavior": "allow"]
        case .allowAlways(let suggestions):
            let rules = (suggestions.array ?? []).filter { $0["behavior"]?.string != "deny" }
            decision = rules.isEmpty ? ["behavior": "allow"] : ["behavior": "allow", "updatedPermissions": .array(rules)]
        case .deny(let message):
            decision = ["behavior": "deny", "message": .string(message)]
        case .askInTerminal:
            return nil
        }
        return ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
    }
}
