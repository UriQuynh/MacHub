// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import Foundation

/// Đọc dần một file rollout của Codex CLI (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`).
///
/// Mỗi dòng: `{"timestamp", "type": session_meta|turn_context|event_msg|response_item, "payload": {...}}`.
/// - `session_meta`: id, cwd, git.branch
/// - `turn_context`: model
/// - `event_msg` `token_count`: info.total_token_usage / last_token_usage, rate_limits.primary/secondary
/// - `event_msg` `task_started` / `task_complete` / `turn_aborted` / `user_message` / `agent_message`
public struct CodexRolloutAccumulator: Sendable {
    public enum State: String, Sendable { case running, finished, idle }

    public private(set) var sessionID: String?
    public private(set) var cwd: String?
    public private(set) var branch: String?
    public private(set) var model: String?
    public private(set) var startedAt: Date?
    public private(set) var lastActivity: Date?
    public private(set) var state: State = .idle
    public private(set) var lastUserMessage: String?
    public private(set) var lastAgentMessage: String?
    public private(set) var totalTokens: Int = 0
    public private(set) var limits: LimitSnapshot?
    /// Bản ghi token mới từ lần `consume` gần nhất (người gọi lấy rồi xóa bằng `drainRecords`).
    public private(set) var pendingRecords: [UsageRecord] = []

    private var lastTotal: Int = -1

    public init() {}

    public mutating func consume(line: String) {
        guard let json = JSONValue.parse(line) else { return }
        consume(json)
    }

    /// Cùng hiệu ứng với `consume(line:)` nhưng không dựng cây JSON cho phần không dùng: dòng `response_item`
    /// (nội dung hội thoại, đầu ra lệnh… chiếm phần lớn rollout) chỉ lấy `timestamp`, `event_msg` không thuộc
    /// các loại được xử lý bị bỏ qua. Sai khác với `consume(line:)` bị chặn bởi `FastParserEquivalenceTests`.
    public mutating func consume(lineBytes line: UnsafeRawBufferPointer) {
        guard let base = line.baseAddress, !line.isEmpty else { return }
        let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: base), count: line.count, deallocator: .none)
        guard let probe = try? JSONDecoder().decode(CodexLineProbe.self, from: data) else { return }
        var json: [String: JSONValue] = [:]
        if let ts = probe.timestamp { json["timestamp"] = .string(ts) }
        if let type = probe.type { json["type"] = .string(type) }
        if let payload = probe.payload { json["payload"] = payload }
        consume(.object(json))
    }

    public mutating func consume(_ json: JSONValue) {
        let ts = ISODate.parse(json["timestamp"]?.string)
        if let ts { lastActivity = max(lastActivity ?? ts, ts) }
        guard let payload = json["payload"] else { return }

        switch json["type"]?.string {
        case "session_meta":
            sessionID = payload["id"]?.string ?? sessionID
            cwd = payload["cwd"]?.string ?? cwd
            branch = payload.path("git", "branch")?.string ?? branch
            startedAt = ISODate.parse(payload["timestamp"]?.string) ?? ts ?? startedAt
            if let m = payload["model"]?.string { model = m }
        case "turn_context":
            if let m = payload["model"]?.string { model = m }
            cwd = payload["cwd"]?.string ?? cwd
        case "event_msg":
            consumeEvent(payload, at: ts)
        default:
            break
        }
    }

    private mutating func consumeEvent(_ p: JSONValue, at ts: Date?) {
        switch p["type"]?.string {
        case "task_started":
            state = .running
        case "task_complete":
            state = .finished
            if let m = p["last_agent_message"]?.string { lastAgentMessage = m }
        case "turn_aborted":
            state = .finished
        case "user_message":
            if let m = p["message"]?.string { lastUserMessage = m }
            state = .running
        case "agent_message":
            if let m = p["message"]?.string { lastAgentMessage = m }
        case "token_count":
            if let info = p["info"], !info.isNull {
                let total = info.path("total_token_usage", "total_tokens")?.int ?? 0
                // Codex đôi khi phát lại cùng token_count: chỉ tính khi tổng tăng.
                if total > lastTotal, let last = info["last_token_usage"], let ts {
                    let input = last["input_tokens"]?.int ?? 0
                    let cached = last["cached_input_tokens"]?.int ?? 0
                    let output = last["output_tokens"]?.int ?? 0
                    pendingRecords.append(UsageRecord(
                        provider: .codex, timestamp: ts, model: model ?? "codex", project: cwd, sessionID: sessionID,
                        inputTokens: max(0, input - cached), outputTokens: output, cacheReadTokens: cached))
                    lastTotal = total
                    totalTokens = total
                }
            }
            if let rl = p["rate_limits"], !rl.isNull, let ts {
                let windows = [("primary", rl["primary"]), ("secondary", rl["secondary"])].compactMap { key, w -> LimitWindow? in
                    guard let w, let pct = w["used_percent"]?.double else { return nil }
                    let minutes = w["window_minutes"]?.int
                    let resets = w["resets_at"]?.double.map { Date(timeIntervalSince1970: $0) }
                        ?? w["resets_in_seconds"]?.double.map { ts.addingTimeInterval($0) }
                    return LimitWindow(id: key, label: LimitLabels.codex(windowMinutes: minutes, fallback: key == "primary" ? "5H" : "7D"),
                                       usedPercent: pct, resetsAt: resets, windowMinutes: minutes)
                }
                if !windows.isEmpty {
                    let plan = rl["plan_type"]?.string
                    limits = LimitSnapshot(provider: .codex, windows: windows, observedAt: ts, source: .codexLog, plan: plan)
                }
            }
        default:
            break
        }
    }

    /// Loại `event_msg` mà `consumeEvent` có xử lý; loại khác không ảnh hưởng trạng thái.
    static let handledEventTypes: Set<String> = [
        "task_started", "task_complete", "turn_aborted", "user_message", "agent_message", "token_count",
    ]

    public mutating func drainRecords() -> [UsageRecord] {
        defer { pendingRecords.removeAll() }
        return pendingRecords
    }
}

/// Đọc file JSONL theo từng phần mới (offset), giữ lại dòng dở dang ở cuối.
public struct IncrementalLineReader: Sendable {
    public private(set) var offset: UInt64 = 0
    private var remainder = Data()

    public init() {}

    /// Đọc phần mới theo từng khối `chunkBytes` và gọi `body` cho mỗi dòng hoàn chỉnh (không rỗng) kể từ lần đọc trước,
    /// KHÔNG gom toàn bộ dòng vào mảng: bộ nhớ chỉ cỡ một khối (cộng dòng dở dang / dòng dài nhất).
    /// `body` nhận byte của dòng (không gồm `\n`), chỉ hợp lệ trong lúc gọi. Dừng sau `maxBytes` byte (phần còn lại để
    /// lần quét sau). File bị cắt ngắn (ghi đè) → đọc lại từ đầu.
    public mutating func forEachNewLine(at url: URL, chunkBytes: Int = 4 * 1024 * 1024, maxBytes: Int = .max,
                                        _ body: (UnsafeRawBufferPointer) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset {
            offset = 0
            remainder.removeAll()
        }
        guard size > offset else { return }
        try? handle.seek(toOffset: offset)
        var left = Int(min(UInt64(maxBytes), size - offset))
        while left > 0 {
            var finished = false
            autoreleasepool {
                guard let data = try? handle.read(upToCount: min(chunkBytes, left)), !data.isEmpty else { finished = true; return }
                left -= data.count
                offset += UInt64(data.count)
                if remainder.isEmpty {
                    remainder = consumeLines(in: data, body)
                } else {
                    var chunk = remainder
                    chunk.append(data)
                    remainder = consumeLines(in: chunk, body)
                }
            }
            if finished { break }
        }
    }

    /// Gọi `body` cho từng dòng hoàn chỉnh trong `chunk`; trả về phần đuôi chưa có `\n`.
    private func consumeLines(in chunk: Data, _ body: (UnsafeRawBufferPointer) -> Void) -> Data {
        chunk.withUnsafeBytes { raw -> Data in
            guard let base = raw.baseAddress else { return Data() }
            var start = 0
            while start < raw.count, let nl = memchr(base + start, 0x0A, raw.count - start) {
                let end = base.distance(to: UnsafeRawPointer(nl))
                if end > start { body(UnsafeRawBufferPointer(start: base + start, count: end - start)) }
                start = end + 1
            }
            return start < raw.count ? Data(raw[start...]) : Data()
        }
    }

    /// Trả về các dòng hoàn chỉnh mới kể từ lần đọc trước (tối đa `maxBytes` byte mỗi lần). Tiện cho test và phần
    /// đọc nhỏ; quét lớn dùng `forEachNewLine` để không giữ cả mảng chuỗi trong bộ nhớ.
    public mutating func readNewLines(at url: URL, maxBytes: Int = 64 * 1024 * 1024) -> [String] {
        var lines: [String] = []
        forEachNewLine(at: url, maxBytes: maxBytes) { lines.append(String(decoding: $0, as: UTF8.self)) }
        return lines
    }
}
