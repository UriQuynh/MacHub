// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import Foundation

/// Đọc transcript JSONL của Claude Code (`~/.claude/projects/<dự án>/<phiên>.jsonl`).
public enum ClaudeTranscript {
    /// Khóa khử trùng lặp: Claude Code có thể ghi cùng một phản hồi nhiều lần (stream, resume, fork).
    public static func dedupeKey(_ line: JSONValue) -> String? {
        guard let id = line.path("message", "id")?.string else { return nil }
        return "\(id):\(line["requestId"]?.string ?? "")"
    }

    /// Một dòng assistant có `message.usage` → bản ghi token. Dòng khác → nil.
    public static func usageRecord(from line: JSONValue) -> UsageRecord? {
        guard line["type"]?.string == "assistant",
              let usage = line.path("message", "usage"), usage.object != nil else { return nil }
        let model = line.path("message", "model")?.string ?? "unknown"
        if model == "<synthetic>" { return nil }
        guard let ts = ISODate.parse(line["timestamp"]?.string) else { return nil }

        let input = usage["input_tokens"]?.int ?? 0
        let output = usage["output_tokens"]?.int ?? 0
        let cacheRead = usage["cache_read_input_tokens"]?.int ?? 0
        var cache5m = usage["cache_creation_input_tokens"]?.int ?? 0
        var cache1h = 0
        if let detail = usage["cache_creation"] {
            let d5 = detail["ephemeral_5m_input_tokens"]?.int
            let d1 = detail["ephemeral_1h_input_tokens"]?.int
            if d5 != nil || d1 != nil {
                cache5m = d5 ?? 0
                cache1h = d1 ?? 0
            }
        }
        if input + output + cacheRead + cache5m + cache1h == 0 { return nil }

        return UsageRecord(provider: .claude, timestamp: ts, model: model,
                           project: line["cwd"]?.string, sessionID: line["sessionId"]?.string,
                           inputTokens: input, outputTokens: output,
                           cacheWrite5mTokens: cache5m, cacheWrite1hTokens: cache1h, cacheReadTokens: cacheRead)
    }

    /// Model của phản hồi assistant gần nhất trong một đoạn cuối transcript.
    public static func lastModel(inTail text: String) -> String? {
        for raw in text.split(separator: "\n").reversed() {
            guard let line = JSONValue.parse(String(raw)), line["type"]?.string == "assistant",
                  let model = line.path("message", "model")?.string, model != "<synthetic>" else { continue }
            return model
        }
        return nil
    }
}

/// Token OAuth trong mục Keychain "Claude Code-credentials" (JSON: `claudeAiOauth.accessToken`, `expiresAt` tính bằng ms).
public struct ClaudeCredentials: Equatable, Sendable {
    public var accessToken: String
    public var expiresAt: Date?

    public init(accessToken: String, expiresAt: Date?) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }

    public static func parse(_ data: Data) -> ClaudeCredentials? {
        guard let json = JSONValue.parse(data), let oauth = json["claudeAiOauth"],
              let token = oauth["accessToken"]?.string, !token.isEmpty else { return nil }
        let exp = oauth["expiresAt"]?.double.map { Date(timeIntervalSince1970: $0 / 1000) }
        return ClaudeCredentials(accessToken: token, expiresAt: exp)
    }

    /// Còn dùng được nếu chưa tới `expiresAt` trừ một khoảng đệm (token không có hạn coi như còn dùng được).
    public func isValid(at now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return true }
        return expiresAt.addingTimeInterval(-leeway) > now
    }
}

/// Phản hồi của `GET https://api.anthropic.com/api/oauth/usage` (không có tài liệu chính thức,
/// nên đọc mềm dẻo: mọi khóa có `utilization` đều được coi là một cửa sổ hạn mức).
public enum ClaudeOAuthUsage {
    public static func parse(_ data: Data, observedAt: Date = Date()) -> LimitSnapshot? {
        guard let obj = JSONValue.parse(data)?.object else { return nil }
        var windows: [LimitWindow] = []
        for (key, value) in obj {
            guard let pct = value["utilization"]?.double else { continue }
            let resets: Date? = value["resets_at"]?.string.flatMap(ISODate.parse)
                ?? value["resets_at"]?.double.map { Date(timeIntervalSince1970: $0) }
            windows.append(LimitWindow(id: key, label: LimitLabels.claude(key), usedPercent: pct, resetsAt: resets))
        }
        guard !windows.isEmpty else { return nil }
        return LimitSnapshot(provider: .claude, windows: sortClaude(windows), observedAt: observedAt, source: .oauth)
    }

    /// 5H, 7D trước; các cửa sổ theo model sau, theo tên.
    public static func sortClaude(_ windows: [LimitWindow]) -> [LimitWindow] {
        let order = ["five_hour": 0, "seven_day": 1]
        return windows.sorted {
            let a = order[$0.id] ?? 2, b = order[$1.id] ?? 2
            return a != b ? a < b : $0.id < $1.id
        }
    }
}

/// JSON mà Claude Code đưa vào lệnh statusLine qua stdin.
public struct ClaudeStatusLine: Equatable, Sendable {
    public var sessionID: String?
    public var modelID: String?
    public var modelName: String?
    public var cwd: String?
    public var transcriptPath: String?
    public var costUSD: Double?
    public var contextUsedPercent: Double?
    public var limits: LimitSnapshot?

    public init(payload: JSONValue, observedAt: Date = Date()) {
        sessionID = payload["session_id"]?.string
        modelID = payload.path("model", "id")?.string
        modelName = payload.path("model", "display_name")?.string
        cwd = payload.path("workspace", "current_dir")?.string ?? payload["cwd"]?.string
        transcriptPath = payload["transcript_path"]?.string
        costUSD = payload.path("cost", "total_cost_usd")?.double
        contextUsedPercent = payload.path("context_window", "used_percentage")?.double

        var windows: [LimitWindow] = []
        if let rl = payload["rate_limits"]?.object {
            for (key, value) in rl {
                guard let pct = value["used_percentage"]?.double ?? value["utilization"]?.double else { continue }
                let resets = value["resets_at"]?.double.map { Date(timeIntervalSince1970: $0) }
                    ?? value["resets_at"]?.string.flatMap(ISODate.parse)
                windows.append(LimitWindow(id: key, label: LimitLabels.claude(key), usedPercent: pct, resetsAt: resets))
            }
        }
        limits = windows.isEmpty ? nil
            : LimitSnapshot(provider: .claude, windows: ClaudeOAuthUsage.sortClaude(windows), observedAt: observedAt, source: .statusLine)
    }

    /// Dòng mặc định khi người dùng chưa có statusLine riêng.
    public var defaultLine: String {
        var parts: [String] = []
        if let modelName { parts.append(modelName) }
        for w in limits?.windows ?? [] where w.id == "five_hour" || w.id == "seven_day" {
            parts.append("\(w.label) \(Int(w.usedPercent.rounded()))%")
        }
        if let contextUsedPercent { parts.append("ctx \(Int(contextUsedPercent.rounded()))%") }
        return parts.joined(separator: " · ")
    }
}
