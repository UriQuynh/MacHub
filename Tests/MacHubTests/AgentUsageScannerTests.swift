// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import AgentKit
import XCTest
@testable import MacHub

/// Bộ quét transcript trên đĩa: kết quả (bản ghi token) phải giữ nguyên so với cách quét cũ dựa trên `JSONValue`,
/// kể cả khi quét tăng dần và khi cùng một phản hồi bị ghi ở nhiều file.
final class AgentUsageScannerTests: XCTestCase {
    private var root: URL!
    private var claudeRoot: URL!
    private var codexRoot: URL!
    private let now = ISODate.parse("2026-11-20T12:00:00Z")!

    override func setUpWithError() throws {
        root = Self.realTemporaryDirectory().appendingPathComponent("machub-scan-\(UUID().uuidString)", isDirectory: true)
        claudeRoot = root.appendingPathComponent("claude/projects", isDirectory: true)
        codexRoot = root.appendingPathComponent("codex/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeRoot.appendingPathComponent("-Users-u-App"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
    }

    /// `/var/folders/…` thật ra là `/private/var/folders/…`; bộ quét đếm độ sâu theo đường dẫn nên cần đường dẫn đã giải symlink.
    private static func realTemporaryDirectory() -> URL {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(FileManager.default.temporaryDirectory.path, &buf) != nil else { return FileManager.default.temporaryDirectory }
        return URL(fileURLWithPath: String(cString: buf), isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func assistant(id: String, request: String = "r", ts: String, input: Int, output: Int, cwd: String = "/Users/u/App") -> String {
        #"{"type":"assistant","timestamp":"\#(ts)","sessionId":"s-\#(id)","cwd":"\#(cwd)","requestId":"\#(request)","message":{"id":"\#(id)","model":"claude-sonnet-5-5","content":[{"type":"text","text":"xin chào \"usage\""}],"usage":{"input_tokens":\#(input),"output_tokens":\#(output)}}}"#
    }

    private func write(_ lines: [String], to name: String, append: Bool = false, trailingNewline: Bool = true) throws -> URL {
        let url = claudeRoot.appendingPathComponent("-Users-u-App").appendingPathComponent(name)
        let text = lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        if append, let h = try? FileHandle(forWritingTo: url) {
            try h.seekToEnd()
            try h.write(contentsOf: Data(text.utf8))
            try h.close()
        } else {
            try Data(text.utf8).write(to: url)
        }
        return url
    }

    private func scan(_ scanner: AgentUsageScanner) -> AgentUsageScanner.Result {
        let done = expectation(description: "scan")
        var result: AgentUsageScanner.Result?
        scanner.scan(now: now) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 30)
        return result!
    }

    /// Cách quét cũ (trước tối ưu): parse đủ cây JSON cho mọi dòng có "usage".
    private func oracleRecords(lines: [String], cutoff: Date) -> [UsageRecord] {
        var seen = Set<String>()
        var out: [UsageRecord] = []
        for line in lines {
            guard line.contains("\"usage\""), let json = JSONValue.parse(line),
                  let r = ClaudeTranscript.usageRecord(from: json), r.timestamp >= cutoff else { continue }
            if let key = ClaudeTranscript.dedupeKey(json) { guard seen.insert(key).inserted else { continue } }
            out.append(r)
        }
        return out
    }

    func testScanMatchesOldBehaviourIncludingDedupeAndRetention() throws {
        let a = [
            assistant(id: "m1", ts: "2026-11-19T10:00:00Z", input: 10, output: 20),
            #"{"type":"user","message":{"content":"hi \"usage\""}}"#,
            assistant(id: "m1", ts: "2026-11-19T10:00:00Z", input: 10, output: 20),  // trùng trong cùng file
            assistant(id: "m2", ts: "2026-11-19T10:01:00.5Z", input: 1, output: 2),
            assistant(id: "old", ts: "2026-09-01T10:00:00Z", input: 99, output: 99),  // quá hạn 31 ngày
            "dòng rác {",
            assistant(id: "zero", ts: "2026-11-19T10:02:00Z", input: 0, output: 0),
        ]
        let b = [
            assistant(id: "m1", ts: "2026-11-19T10:00:00Z", input: 10, output: 20),  // trùng giữa hai file (resume/fork)
            assistant(id: "m3", ts: "2026-11-18T09:00:00Z", input: 7, output: 8, cwd: "/Users/u/Khác"),
        ]
        _ = try write(a, to: "a.jsonl")
        _ = try write(b, to: "b.jsonl")

        let scanner = AgentUsageScanner(claudeRoots: [claudeRoot], codexRoot: codexRoot)
        let got = scan(scanner).records
        let cutoff = now.addingTimeInterval(-AgentUsageScanner.retention)
        // Thứ tự file không cố định (theo mtime): so sánh theo tập đã sắp xếp; bản ghi trùng chỉ được tính một lần.
        let key: (UsageRecord) -> String = { "\($0.timestamp.timeIntervalSince1970)|\($0.sessionID ?? "")|\($0.inputTokens)|\($0.project ?? "")" }
        let expected = Set((oracleRecords(lines: a, cutoff: cutoff) + oracleRecords(lines: b, cutoff: cutoff)).map(key))
        XCTAssertEqual(Set(got.map(key)), expected)
        XCTAssertEqual(got.count, 3, "m1 (một lần), m2, m3")
        XCTAssertEqual(got.filter { $0.project == "/Users/u/Khác" }.first?.outputTokens, 8)
    }

    func testIncrementalScanReadsOnlyAppendedLinesAndKeepsPartialLine() throws {
        let url = try write([assistant(id: "m1", ts: "2026-11-19T10:00:00Z", input: 1, output: 1)], to: "s.jsonl")
        let scanner = AgentUsageScanner(claudeRoots: [claudeRoot], codexRoot: codexRoot)
        XCTAssertEqual(scan(scanner).records.count, 1)
        XCTAssertEqual(scan(scanner).records.count, 1, "Quét lại không đếm đôi")

        // Ghi dở một dòng (chưa có \n) rồi ghi nốt.
        let full = assistant(id: "m2", ts: "2026-11-19T11:00:00Z", input: 5, output: 6)
        let cut = full.index(full.startIndex, offsetBy: 60)
        _ = try write([String(full[..<cut])], to: "s.jsonl", append: true, trailingNewline: false)
        XCTAssertEqual(scan(scanner).records.count, 1, "Dòng dở dang chưa được tính")
        _ = try write([String(full[cut...])], to: "s.jsonl", append: true)
        let after = scan(scanner).records
        XCTAssertEqual(after.count, 2)
        XCTAssertEqual(after.map(\.inputTokens).sorted(), [1, 5])
        _ = url
    }

    func testRepeatedStringsAreSharedButValuesUnchanged() throws {
        _ = try write((0..<20).map { assistant(id: "m\($0)", ts: "2026-11-19T10:00:\(String(format: "%02d", $0))Z", input: $0 + 1, output: 1) },
                      to: "many.jsonl")
        let scanner = AgentUsageScanner(claudeRoots: [claudeRoot], codexRoot: codexRoot)
        let records = scan(scanner).records
        XCTAssertEqual(records.count, 20)
        XCTAssertTrue(records.allSatisfy { $0.model == "claude-sonnet-5-5" && $0.project == "/Users/u/App" })
        XCTAssertEqual(Set(records.compactMap(\.sessionID)).count, 20)
    }

    func testCodexRolloutScan() throws {
        let day = codexRoot.appendingPathComponent("2026/11/19", isDirectory: true)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let lines = [
            #"{"timestamp":"2026-11-19T09:00:00.000Z","type":"session_meta","payload":{"id":"cx-9","cwd":"/Users/u/MacHub","git":{"branch":"main"}}}"#,
            #"{"timestamp":"2026-11-19T09:00:01.000Z","type":"turn_context","payload":{"model":"gpt-5.3-codex"}}"#,
            #"{"timestamp":"2026-11-19T09:00:02.000Z","type":"response_item","payload":{"type":"message","content":"rất dài"}}"#,
            #"{"timestamp":"2026-11-19T09:00:10.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":300},"last_token_usage":{"input_tokens":200,"cached_input_tokens":50,"output_tokens":100}},"rate_limits":{"primary":{"used_percent":4.0,"window_minutes":300},"plan_type":"pro"}}}"#,
            #"{"timestamp":"2026-11-19T09:00:20.000Z","type":"event_msg","payload":{"type":"task_complete","last_agent_message":"xong"}}"#,
        ]
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: day.appendingPathComponent("rollout-2026-11-19-cx-9.jsonl"))
        let scanner = AgentUsageScanner(claudeRoots: [claudeRoot], codexRoot: codexRoot)
        let r = scan(scanner)
        let s = try XCTUnwrap(r.codexSessions.first)
        XCTAssertEqual(s.sessionID, "cx-9")
        XCTAssertEqual(s.branch, "main")
        XCTAssertEqual(s.model, "gpt-5.3-codex")
        XCTAssertEqual(s.state, .finished)
        XCTAssertEqual(s.lastAgentMessage, "xong")
        XCTAssertEqual(s.totalTokens, 300)
        XCTAssertEqual(s.lastActivity, ISODate.parse("2026-11-19T09:00:20.000Z"))
        XCTAssertEqual(r.records.filter { $0.provider == .codex }.map(\.inputTokens), [150])
        XCTAssertEqual(r.codexLimits?.plan, "pro")
    }
}
