// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import AgentKit
import Foundation

/// Quét transcript Claude Code và rollout Codex trên đĩa, đọc tăng dần (chỉ phần mới ghi thêm).
/// Chạy trên hàng đợi nền riêng; mọi trạng thái nằm trong class này (không chia sẻ luồng).
final class AgentUsageScanner: @unchecked Sendable {
    struct CodexSessionInfo: Equatable {
        var path: String
        var sessionID: String
        var cwd: String?
        var branch: String?
        var model: String?
        var state: CodexRolloutAccumulator.State
        var lastUserMessage: String?
        var lastAgentMessage: String?
        var startedAt: Date?
        var lastActivity: Date?
        var totalTokens: Int
    }

    struct Result {
        var records: [UsageRecord]
        var codexSessions: [CodexSessionInfo]
        var codexLimits: LimitSnapshot?
    }

    /// Chỉ giữ dữ liệu trong cửa sổ này (đủ cho bộ lọc "30 ngày").
    static let retention: TimeInterval = 31 * 86_400
    /// Giới hạn số file đọc mỗi lần quét để không làm nóng máy khi lịch sử rất lớn.
    static let maxFilesPerScan = 4_000

    private struct ClaudeFile {
        var reader = IncrementalLineReader()
    }

    private struct CodexFile {
        var reader = IncrementalLineReader()
        var acc = CodexRolloutAccumulator()
    }

    private var claudeFiles: [String: ClaudeFile] = [:]
    private var codexFiles: [String: CodexFile] = [:]
    private var seenClaudeKeys = Set<String>()
    private var records: [UsageRecord] = []

    let queue = DispatchQueue(label: "com.machub.app.agent-scan", qos: .utility)

    func scan(now: Date = Date(), completion: @escaping (Result) -> Void) {
        queue.async { [self] in
            let cutoff = now.addingTimeInterval(-Self.retention)
            scanClaude(cutoff: cutoff)
            let (sessions, limits) = scanCodex(cutoff: cutoff)
            records.removeAll { $0.timestamp < cutoff }
            completion(Result(records: records, codexSessions: sessions, codexLimits: limits))
        }
    }

    // MARK: Claude

    private func scanClaude(cutoff: Date) {
        var budget = Self.maxFilesPerScan
        for root in AgentPaths.claudeProjectDirectories {
            for url in jsonlFiles(under: root, modifiedAfter: cutoff, maxDepth: 4) {
                guard budget > 0 else { return }
                budget -= 1
                var file = claudeFiles[url.path] ?? ClaudeFile()
                for line in file.reader.readNewLines(at: url) {
                    // Lọc nhanh trước khi parse JSON: chỉ dòng assistant có usage.
                    guard line.contains("\"usage\""), let json = JSONValue.parse(line),
                          let record = ClaudeTranscript.usageRecord(from: json), record.timestamp >= cutoff else { continue }
                    if let key = ClaudeTranscript.dedupeKey(json) {
                        guard seenClaudeKeys.insert(key).inserted else { continue }
                    }
                    records.append(record)
                }
                claudeFiles[url.path] = file
            }
        }
    }

    // MARK: Codex

    private func scanCodex(cutoff: Date) -> ([CodexSessionInfo], LimitSnapshot?) {
        var sessions: [CodexSessionInfo] = []
        var latestLimits: LimitSnapshot?
        let files = jsonlFiles(under: AgentPaths.codexSessionsDirectory, modifiedAfter: cutoff, maxDepth: 4)
            .filter { $0.lastPathComponent.hasPrefix("rollout-") }
        for url in files.prefix(Self.maxFilesPerScan) {
            var file = codexFiles[url.path] ?? CodexFile()
            for line in file.reader.readNewLines(at: url) { file.acc.consume(line: line) }
            records.append(contentsOf: file.acc.drainRecords().filter { $0.timestamp >= cutoff })
            codexFiles[url.path] = file

            let a = file.acc
            if let l = a.limits, l.observedAt > (latestLimits?.observedAt ?? .distantPast) { latestLimits = l }
            let sid = a.sessionID ?? url.deletingPathExtension().lastPathComponent
            sessions.append(CodexSessionInfo(
                path: url.path, sessionID: sid, cwd: a.cwd, branch: a.branch, model: a.model, state: a.state,
                lastUserMessage: a.lastUserMessage, lastAgentMessage: a.lastAgentMessage,
                startedAt: a.startedAt, lastActivity: a.lastActivity, totalTokens: a.totalTokens))
        }
        return (sessions, latestLimits)
    }

    // MARK: File

    private func jsonlFiles(under root: URL, modifiedAfter cutoff: Date, maxDepth: Int) -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        var out: [(URL, Date)] = []
        let rootDepth = root.pathComponents.count
        for case let url as URL in e {
            if url.pathComponents.count - rootDepth > maxDepth { e.skipDescendants(); continue }
            guard url.pathExtension == "jsonl",
                  let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                  let m = v.contentModificationDate, m >= cutoff else { continue }
            out.append((url, m))
        }
        // Mới nhất trước: nếu chạm giới hạn thì bỏ file cũ.
        return out.sorted { $0.1 > $1.1 }.map(\.0)
    }
}
