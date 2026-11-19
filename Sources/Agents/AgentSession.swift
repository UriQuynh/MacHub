// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import AgentKit
import Foundation

/// Một phiên agent (Claude Code hoặc Codex) đang được theo dõi.
struct AgentSession: Identifiable, Equatable {
    enum State: String, Equatable {
        case idle           // vừa mở phiên, chưa nhận lệnh
        case running        // đang làm việc
        case waitingApproval // chờ duyệt quyền
        case waitingInput   // chờ người dùng nhập
        case finished       // xong lượt
        case subagentDone   // một subagent vừa xong
        case ended          // phiên đã đóng
    }

    let id: String
    let provider: AgentProvider
    let sessionID: String
    var title: String?
    var cwd: String?
    var repo: String?
    var branch: String?
    var model: String?
    var state: State
    var lastPrompt: String?
    var lastMessage: String?
    var startedAt: Date
    var updatedAt: Date
    var runningSubagents: Int = 0
    var parentPID: Int32?

    init(provider: AgentProvider, sessionID: String, now: Date = Date()) {
        self.id = "\(provider.rawValue):\(sessionID)"
        self.provider = provider
        self.sessionID = sessionID
        self.state = .finished
        self.startedAt = now
        self.updatedAt = now
    }

    /// Phiên đang bận hoặc đang cần bạn (subagent xong nhưng agent chính vẫn chạy).
    var isActive: Bool { [.running, .waitingApproval, .waitingInput, .subagentDone].contains(state) }

    var stateLabel: String {
        switch state {
        case .idle: return tr("Sẵn sàng", "Ready")
        case .running: return runningSubagents > 0 ? tr("Đang chạy · \(runningSubagents) subagent", "Running · \(runningSubagents) subagents") : tr("Đang chạy", "Running")
        case .waitingApproval: return tr("Chờ duyệt quyền", "Needs approval")
        case .waitingInput: return tr("Chờ bạn", "Waiting for you")
        case .finished: return tr("Đã xong", "Finished")
        case .subagentDone: return tr("Subagent xong", "Subagent finished")
        case .ended: return tr("Đã đóng", "Ended")
        }
    }

    /// Tên hiển thị: tiêu đề phiên → repo → thư mục.
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if let repo { return repo }
        if let cwd { return (cwd as NSString).lastPathComponent }
        return String(sessionID.prefix(8))
    }

    /// Tên model rút gọn: "claude-sonnet-5-5-20260601" → "sonnet-5-5".
    var shortModel: String? {
        guard let model else { return nil }
        return PriceBook.normalize(model)
    }
}

/// Một yêu cầu quyền đang chờ người dùng quyết định.
struct PendingApproval: Identifiable {
    let id: UUID
    let sessionKey: String
    let toolName: String
    let summary: String
    let detail: String?
    let cwd: String?
    let suggestions: JSONValue?
    let createdAt: Date
    let respond: (PermissionDecision) -> Void

    var project: String? { cwd.map { ($0 as NSString).lastPathComponent } }

    /// Tóm tắt dễ đọc từ `tool_input` (lệnh Bash, đường dẫn file, URL…).
    static func describe(tool: String, input: JSONValue?) -> (summary: String, detail: String?) {
        guard let input else { return (tool, nil) }
        if let cmd = input["command"]?.string {
            return (cmd, input["description"]?.string)
        }
        if let path = input["file_path"]?.string ?? input["notebook_path"]?.string ?? input["path"]?.string {
            return (path, nil)
        }
        if let url = input["url"]?.string { return (url, input["prompt"]?.string) }
        if let pattern = input["pattern"]?.string { return (pattern, nil) }
        let json = input.compactString
        return (json.count > 300 ? String(json.prefix(300)) + "…" : json, nil)
    }
}

enum GitInfo {
    /// Tên repo + nhánh hiện tại, đọc thẳng từ `.git` (không chạy tiến trình git).
    static func lookup(cwd: String) -> (repo: String?, branch: String?) {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: cwd, isDirectory: true)
        for _ in 0..<12 {
            let git = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: git.path, isDirectory: &isDir) {
                var gitDir = git
                if !isDir.boolValue,
                   let text = try? String(contentsOf: git, encoding: .utf8),
                   let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) {
                    // Worktree / submodule: file .git trỏ tới thư mục git thật.
                    let p = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
                    gitDir = URL(fileURLWithPath: p, relativeTo: dir).standardizedFileURL
                }
                let head = (try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8)) ?? ""
                let branch: String? = head.hasPrefix("ref: refs/heads/")
                    ? String(head.dropFirst("ref: refs/heads/".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    : (head.isEmpty ? nil : String(head.prefix(7)))
                return (dir.lastPathComponent, branch)
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return ((cwd as NSString).lastPathComponent, nil)
    }
}
