// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import XCTest
@testable import AgentKit

/// Đường quét nhanh (`ClaudeTranscript.scan`, `CodexRolloutAccumulator.consume(lineBytes:)`, `forEachNewLine`)
/// phải cho đúng kết quả của đường chậm dựa trên `JSONValue` — là thứ quyết định số liệu hiển thị.
final class FastParserEquivalenceTests: XCTestCase {
    // MARK: Claude

    /// Đường chậm cũ, nguyên văn từ `AgentUsageScanner` trước khi tối ưu.
    private func claudeOracle(_ line: String) -> ClaudeTranscript.ScannedLine? {
        guard line.contains("\"usage\""), let json = JSONValue.parse(line),
              let record = ClaudeTranscript.usageRecord(from: json) else { return nil }
        return ClaudeTranscript.ScannedLine(record: record, dedupeKey: ClaudeTranscript.dedupeKey(json))
    }

    private func assertSameClaude(_ line: String, file: StaticString = #filePath, line ln: UInt = #line) {
        XCTAssertEqual(ClaudeTranscript.scan(line: line), claudeOracle(line), "Khác kết quả với: \(line.prefix(200))",
                       file: file, line: ln)
    }

    private let claudeCorpus: [String] = [
        // Bình thường, có tách cache 5m/1h.
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00.123Z","sessionId":"s1","cwd":"/Users/u/P","requestId":"req_1","message":{"id":"msg_1","model":"claude-sonnet-5-5","usage":{"input_tokens":12,"output_tokens":340,"cache_creation_input_tokens":1000,"cache_read_input_tokens":20000,"cache_creation":{"ephemeral_5m_input_tokens":600,"ephemeral_1h_input_tokens":400}}}}"#,
        // Không có cache_creation chi tiết → dùng cache_creation_input_tokens.
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00Z","message":{"id":"m2","model":"m","usage":{"input_tokens":5,"output_tokens":6,"cache_creation_input_tokens":70}}}"#,
        // Chỉ có một nửa chi tiết.
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00Z","message":{"id":"m3","model":"m","usage":{"input_tokens":1,"cache_creation_input_tokens":99,"cache_creation":{"ephemeral_1h_input_tokens":3}}}}"#,
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00Z","message":{"id":"m3","model":"m","usage":{"input_tokens":1,"cache_creation_input_tokens":99,"cache_creation":{"ephemeral_5m_input_tokens":4}}}}"#,
        // cache_creation rỗng / không phải object.
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00Z","message":{"id":"m4","model":"m","usage":{"input_tokens":1,"cache_creation_input_tokens":9,"cache_creation":{}}}}"#,
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00Z","message":{"id":"m4","model":"m","usage":{"input_tokens":1,"cache_creation_input_tokens":9,"cache_creation":[1,2]}}}"#,
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00Z","message":{"id":"m4","model":"m","usage":{"input_tokens":1,"cache_creation":null}}}"#,
        // Số dưới dạng chuỗi, chuỗi không phải số, bool, số thực, âm.
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00Z","message":{"id":"m5","model":"m","usage":{"input_tokens":"12","output_tokens":"abc","cache_read_input_tokens":true}}}"#,
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00Z","message":{"id":"m6","model":"m","usage":{"input_tokens":12.9,"output_tokens":-3,"cache_read_input_tokens":1e3}}}"#,
        // usage không phải object.
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00Z","message":{"id":"m7","model":"m","usage":null}}"#,
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00Z","message":{"id":"m7","model":"m","usage":[1]}}"#,
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00Z","message":{"id":"m7","model":"m","usage":7}}"#,
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00Z","message":{"id":"m7","model":"m","usage":{}}}"#,
        // Toàn 0 → bỏ.
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00Z","message":{"id":"m8","model":"m","usage":{"input_tokens":0,"output_tokens":0}}}"#,
        // Loại khác / synthetic / thiếu model.
        #"{"type":"user","timestamp":"2026-11-18T10:00:00Z","message":{"id":"m9","model":"m","usage":{"input_tokens":1}}}"#,
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00Z","message":{"id":"m10","model":"<synthetic>","usage":{"input_tokens":1,"output_tokens":1}}}"#,
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00Z","message":{"id":"m11","usage":{"input_tokens":1}}}"#,
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00Z","message":{"id":"m11","model":5,"usage":{"input_tokens":1}}}"#,
        #"{"type":7,"timestamp":"2026-11-18T10:00:00Z","message":{"id":"m11","model":"m","usage":{"input_tokens":1}}}"#,
        // Thời gian thiếu / sai / dạng số.
        #"{"type":"assistant","message":{"id":"m12","model":"m","usage":{"input_tokens":1}}}"#,
        #"{"type":"assistant","timestamp":"hôm qua","message":{"id":"m12","model":"m","usage":{"input_tokens":1}}}"#,
        #"{"type":"assistant","timestamp":1731900000,"message":{"id":"m12","model":"m","usage":{"input_tokens":1}}}"#,
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00+07:00","message":{"id":"m12","model":"m","usage":{"input_tokens":1}}}"#,
        // Khóa định danh thiếu / sai kiểu.
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00Z","cwd":5,"sessionId":null,"requestId":3,"message":{"id":"m13","model":"m","usage":{"input_tokens":1}}}"#,
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00Z","message":{"model":"m","usage":{"input_tokens":1}}}"#,
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00Z","message":{"id":9,"model":"m","usage":{"input_tokens":1}}}"#,
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00Z","message":"usage","usage":{"input_tokens":1}}"#,
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00Z","usage":{"input_tokens":1}}"#,
        // Nội dung dài có chữ "usage" ở chỗ khác, escape, unicode, xuống dòng đã escape.
        #"{"type":"user","message":{"content":[{"type":"tool_result","content":"\"usage\": {\"input_tokens\": 5}\n"}]}}"#,
        #"{"type":"assistant","timestamp":"2026-11-18T10:00:00Z","cwd":"/Users/u/Dự án \"lạ\" ✓","sessionId":"é","message":{"id":"m14é","model":"m","content":[{"type":"text","text":"x\n\"usage\" \u0000 😀"},{"type":"tool_use","input":{"a":[1,2,{"b":null}]}}],"usage":{"input_tokens":3,"output_tokens":4}}}"#,
        // Pretty-printed.
        "{\n \"type\" : \"assistant\" ,\n \"timestamp\":\"2026-11-18T10:00:00Z\",\n \"message\":{ \"id\":\"m15\", \"model\":\"m\", \"usage\": { \"input_tokens\" : 2 } }\n}",
        // Rác.
        "", "usage", #""usage""#, #"["usage"]"#, #"{"usage":1}"#, #"{"type":"assistant","usage"#, "not json \"usage\"", "null", "{}",
    ]

    func testClaudeCorpusMatchesSlowPath() {
        for line in claudeCorpus { assertSameClaude(line) }
    }

    func testClaudeCorpusProducesRecordsWhereExpected() throws {
        let first = try XCTUnwrap(ClaudeTranscript.scan(line: claudeCorpus[0]))
        XCTAssertEqual(first.record.cacheWrite5mTokens, 600)
        XCTAssertEqual(first.record.cacheWrite1hTokens, 400)
        XCTAssertEqual(first.record.inputTokens, 12)
        XCTAssertEqual(first.dedupeKey, "msg_1:req_1")
        XCTAssertEqual(first.record.project, "/Users/u/P")
        // Chữ "usage" chỉ nằm trong nội dung tool_result → không phải bản ghi.
        XCTAssertNil(ClaudeTranscript.scan(line: claudeCorpus[27]))
    }

    func testClaudeRandomizedLinesMatchSlowPath() {
        var rng = SplitMix64(seed: 0xC1A0DE)
        func pick<T>(_ xs: [T]) -> T { xs[Int(rng.next() % UInt64(xs.count))] }
        let numbers = ["0", "1", "17", "12.9", "-3", "\"42\"", "\"x\"", "null", "true", "[]", "{}", "1e3", "250000"]
        let strings = ["\"abc\"", "\"\"", "null", "5", "true", "{}", "\"<synthetic>\"", "\"claude-opus-5-5\""]
        let stamps = ["\"2026-11-18T10:00:00.5Z\"", "\"2026-11-18T10:00:00Z\"", "\"bad\"", "null", "12"]
        for _ in 0..<3_000 {
            var usage: [String] = []
            for (k, opts) in [("input_tokens", numbers), ("output_tokens", numbers), ("cache_read_input_tokens", numbers),
                              ("cache_creation_input_tokens", numbers)] where rng.next() % 4 != 0 {
                usage.append("\"\(k)\":\(pick(opts))")
            }
            if rng.next() % 3 == 0 {
                var d: [String] = []
                if rng.next() % 2 == 0 { d.append("\"ephemeral_5m_input_tokens\":\(pick(numbers))") }
                if rng.next() % 2 == 0 { d.append("\"ephemeral_1h_input_tokens\":\(pick(numbers))") }
                usage.append("\"cache_creation\":" + pick(["{" + d.joined(separator: ",") + "}", "null", "[1]", "5"]))
            }
            let usageJSON = pick(["{" + usage.joined(separator: ",") + "}", "{" + usage.joined(separator: ",") + "}",
                                  "{" + usage.joined(separator: ",") + "}", "null", "[]", "3"])
            var msg: [String] = []
            if rng.next() % 5 != 0 { msg.append("\"id\":\(pick(strings))") }
            if rng.next() % 5 != 0 { msg.append("\"model\":\(pick(strings))") }
            msg.append("\"content\":[{\"type\":\"text\",\"text\":\"…\"}]")
            msg.append("\"usage\":\(usageJSON)")
            var top: [String] = []
            top.append("\"type\":" + pick(["\"assistant\"", "\"assistant\"", "\"assistant\"", "\"user\"", "1", "null"]))
            if rng.next() % 6 != 0 { top.append("\"timestamp\":\(pick(stamps))") }
            if rng.next() % 2 == 0 { top.append("\"cwd\":\(pick(strings))") }
            if rng.next() % 2 == 0 { top.append("\"sessionId\":\(pick(strings))") }
            if rng.next() % 2 == 0 { top.append("\"requestId\":\(pick(strings))") }
            top.append("\"message\":" + pick(["{" + msg.joined(separator: ",") + "}", "{" + msg.joined(separator: ",") + "}", "\"s\"", "null"]))
            let line = "{" + top.shuffled(using: &rng).joined(separator: ",") + "}"
            assertSameClaude(line)
        }
    }

    // MARK: Codex

    private static let rollout: [String] = [
        #"{"timestamp":"2026-11-18T09:00:00.000Z","type":"session_meta","payload":{"id":"cx-1","cwd":"/Users/u/MacHub","git":{"branch":"agent-monitor"},"timestamp":"2026-11-18T08:59:59.000Z"}}"#,
        #"{"timestamp":"2026-11-18T09:00:01.000Z","type":"turn_context","payload":{"model":"gpt-5.3-codex","cwd":"/Users/u/MacHub2"}}"#,
        #"{"timestamp":"2026-11-18T09:00:02.000Z","type":"event_msg","payload":{"type":"task_started"}}"#,
        #"{"timestamp":"2026-11-18T09:00:03.000Z","type":"event_msg","payload":{"type":"user_message","message":"viết test"}}"#,
        #"{"timestamp":"2026-11-18T09:00:04.000Z","type":"response_item","payload":{"type":"function_call_output","output":"\"usage\" rất dài \n é"}}"#,
        #"{"timestamp":"2026-11-18T09:00:05.000Z","type":"event_msg","payload":{"type":"agent_reasoning","text":"nghĩ"}}"#,
        #"{"timestamp":"2026-11-18T09:00:06.000Z","type":"event_msg","payload":{"type":"agent_message","message":"đang làm"}}"#,
        #"{"timestamp":"2026-11-18T09:00:10.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":600,"output_tokens":200,"total_tokens":1200},"last_token_usage":{"input_tokens":1000,"cached_input_tokens":600,"output_tokens":200,"total_tokens":1200}},"rate_limits":{"primary":{"used_percent":4.0,"window_minutes":300,"resets_at":1795000000},"secondary":{"used_percent":13.0,"window_minutes":10080,"resets_in_seconds":3600},"plan_type":"pro"}}}"#,
        #"{"timestamp":"2026-11-18T09:00:10.100Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":1200},"last_token_usage":{"input_tokens":1000,"cached_input_tokens":600,"output_tokens":200}},"rate_limits":null}}"#,
        #"{"timestamp":"2026-11-18T09:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":1500},"last_token_usage":{"input_tokens":250,"cached_input_tokens":0,"output_tokens":50}}}}"#,
        #"{"timestamp":"2026-11-18T09:01:05.000Z","type":"event_msg","payload":{"type":"task_complete","last_agent_message":"Xong 12 test"}}"#,
        #"{"timestamp":"2026-11-18T09:01:06.000Z","type":"event_msg","payload":{"type":"turn_aborted"}}"#,
    ]

    private static let codexOdd: [String] = [
        // payload null / thiếu / không phải object, timestamp lạ, loại lạ.
        #"{"timestamp":"2026-11-18T09:02:00.000Z","type":"session_meta","payload":null}"#,
        #"{"timestamp":"2026-11-18T09:02:01.000Z","type":"session_meta"}"#,
        #"{"timestamp":"2026-11-18T09:02:02.000Z","type":"turn_context","payload":"x"}"#,
        #"{"timestamp":"2026-11-18T09:02:03.000Z","type":"event_msg","payload":null}"#,
        #"{"timestamp":"2026-11-18T09:02:04.000Z","type":"event_msg","payload":[1]}"#,
        #"{"timestamp":"2026-11-18T09:02:05.000Z","type":"event_msg","payload":{"type":5}}"#,
        #"{"timestamp":"2026-11-18T09:02:06.000Z","type":"event_msg","payload":{"type":"task_complete","last_agent_message":7}}"#,
        #"{"timestamp":5,"type":"event_msg","payload":{"type":"task_started"}}"#,
        #"{"type":"event_msg","payload":{"type":"user_message","message":"không có timestamp"}}"#,
        #"{"timestamp":"2026-11-18T09:02:07.000Z","type":"nope","payload":{"type":"task_started"}}"#,
        #"{"timestamp":"2026-11-18T09:02:08.000Z","payload":{"type":"task_started"}}"#,
        #"{"timestamp":"2026-11-18T09:02:09.000Z","type":"response_item"}"#,
        #"{"timestamp":"2026-11-18T09:02:10.000Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":"9"},"plan_type":3}}}"#,
        #"{"timestamp":"2026-11-18T09:02:11.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":"9000"},"last_token_usage":{"input_tokens":"4","output_tokens":2}}}}"#,
        "not json", "", "[]", "{}", #"{"timestamp":"2026-11-18T09:03:00.000Z""#,
    ]

    private func snapshot(_ a: CodexRolloutAccumulator) -> String {
        let recs = a.pendingRecords.map { "\($0)" }.joined(separator: ";")
        return [a.sessionID, a.cwd, a.branch, a.model, a.startedAt.map { "\($0.timeIntervalSince1970)" },
                a.lastActivity.map { "\($0.timeIntervalSince1970)" }, a.state.rawValue, a.lastUserMessage, a.lastAgentMessage,
                "\(a.totalTokens)", a.limits.map { "\($0)" }, recs].map { $0 ?? "nil" }.joined(separator: "|")
    }

    private func consumeBytes(_ acc: inout CodexRolloutAccumulator, _ line: String) {
        var line = line
        line.withUTF8 { acc.consume(lineBytes: UnsafeRawBufferPointer($0)) }
    }

    func testCodexFastPathMatchesSlowPathLineByLine() {
        var slow = CodexRolloutAccumulator(), fast = CodexRolloutAccumulator()
        for line in Self.rollout + Self.codexOdd + Self.rollout {
            slow.consume(line: line)
            consumeBytes(&fast, line)
            XCTAssertEqual(snapshot(fast), snapshot(slow), "Khác sau dòng: \(line.prefix(120))")
        }
        XCTAssertEqual(fast.totalTokens, 9000)
    }

    func testCodexRandomOrderMatchesSlowPath() {
        var rng = SplitMix64(seed: 0xC0DE)
        let pool = Self.rollout + Self.codexOdd
        for _ in 0..<300 {
            var slow = CodexRolloutAccumulator(), fast = CodexRolloutAccumulator()
            for _ in 0..<12 {
                let line = pool[Int(rng.next() % UInt64(pool.count))]
                slow.consume(line: line)
                consumeBytes(&fast, line)
            }
            XCTAssertEqual(snapshot(fast), snapshot(slow))
            XCTAssertEqual(fast.drainRecords(), slow.drainRecords())
        }
    }

    func testEveryHandledEventTypeIsActuallyHandled() {
        // `handledEventTypes` phải đúng bằng các nhánh của consumeEvent: loại trong danh sách mà không xử lý, hay xử lý mà
        // quên trong danh sách, đều làm đường nhanh lệch đường chậm.
        for type in CodexRolloutAccumulator.handledEventTypes.union(["agent_reasoning", "exec_command_end", "x"]) {
            let line = #"{"timestamp":"2026-11-18T09:00:00.000Z","type":"event_msg","payload":{"type":"\#(type)","message":"m","last_agent_message":"l","info":{"total_token_usage":{"total_tokens":5},"last_token_usage":{"input_tokens":5}}}}"#
            var slow = CodexRolloutAccumulator(), fast = CodexRolloutAccumulator()
            slow.consume(line: line)
            consumeBytes(&fast, line)
            XCTAssertEqual(snapshot(fast), snapshot(slow), type)
        }
    }

    // MARK: Ngày giờ

    func testFastDateParsingMatchesFormatterExactly() {
        var rng = SplitMix64(seed: 0xDA7E)
        func r(_ lo: Int, _ hi: Int) -> Int { lo + Int(rng.next() % UInt64(hi - lo + 1)) }
        for _ in 0..<20_000 {
            let base = String(format: "%04d-%02d-%02dT%02d:%02d:%02d", r(2023, 2028), r(1, 12), r(1, 28), r(0, 23), r(0, 59), r(0, 59))
            for s in [base + "Z", base + String(format: ".%03dZ", r(0, 999))] {
                let fast = ISODate.parseFast(s)
                XCTAssertEqual(fast, ISODate.parseWithFormatters(s), s)
                XCTAssertNotNil(fast, s)
            }
        }
    }

    func testDateParsingFallsBackForUnusualInputsWithSameResult() {
        let cases = ["2026-02-29T10:00:00Z", "2024-02-29T10:00:00Z", "2026-02-30T10:00:00Z", "2026-13-01T10:00:00Z", "2026-11-18T24:00:00Z",
                     "2026-11-18T10:00:60Z", "2026-11-18T10:00:00.5Z", "2026-11-18T10:00:00.123456Z", "2026-11-18T10:00:00+07:00",
                     "2026-11-18T10:00:00.123+07:00", "2026-11-18t10:00:00z", "2026-11-18 10:00:00Z", "1969-12-31T23:59:59Z",
                     "2026-11-18T10:00:00", "2026-11-18", "", "x", "2026-11-18T1x:00:00Z", "2026-11-18T10:00:00.12xZ",
                     "9999-12-31T23:59:59.999Z", "0001-01-01T00:00:00Z", "2026-11-18T10:00:00.000Z", "2000-02-29T00:00:00Z"]
        for s in cases {
            XCTAssertEqual(ISODate.parse(s), ISODate.parseWithFormatters(s), "Khác với formatter: \(s)")
        }
        XCTAssertNil(ISODate.parse(nil))
        XCTAssertNil(ISODate.parse(""))
        XCTAssertEqual(ISODate.parse("2026-11-18T10:00:00.123Z")?.timeIntervalSince1970, 1_794_996_000.123)
    }

    // MARK: Bộ đọc theo khối

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mh-fast-\(UUID().uuidString).jsonl")
    }

    private func collect(_ r: inout IncrementalLineReader, _ url: URL, chunk: Int, maxBytes: Int = .max) -> [String] {
        var out: [String] = []
        r.forEachNewLine(at: url, chunkBytes: chunk, maxBytes: maxBytes) { out.append(String(decoding: $0, as: UTF8.self)) }
        return out
    }

    func testStreamingReaderGivesSameLinesForEveryChunkSize() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let lines = ["a", "", "bb", String(repeating: "x", count: 5_000), "dòng tiếng Việt ✓ 😀", "", "z"]
        try Data((lines.joined(separator: "\n") + "\npartial").utf8).write(to: url)
        let expected = lines.filter { !$0.isEmpty }
        for chunk in [1, 2, 3, 7, 64, 4_096, 1 << 20] {
            var r = IncrementalLineReader()
            XCTAssertEqual(collect(&r, url, chunk: chunk), expected, "chunk \(chunk)")
            XCTAssertEqual(collect(&r, url, chunk: chunk), [], "không đọc lại, chunk \(chunk)")
        }
    }

    func testStreamingReaderHonoursByteBudgetAndResumes() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let lines = (0..<50).map { "line-\($0)-" + String(repeating: "y", count: 40) }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        var r = IncrementalLineReader()
        var got: [String] = []
        var rounds = 0
        while got.count < lines.count, rounds < 100 {
            got += collect(&r, url, chunk: 100, maxBytes: 300)
            rounds += 1
        }
        XCTAssertEqual(got, lines, "Đọc từng phần có giới hạn byte vẫn ra đủ, đúng thứ tự, không trùng")
        XCTAssertGreaterThan(rounds, 1)
    }

    func testStreamingReaderKeepsPartialLineAndResetsOnTruncate() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("a\nb\npart".utf8).write(to: url)
        var r = IncrementalLineReader()
        XCTAssertEqual(collect(&r, url, chunk: 2), ["a", "b"])
        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd()
        try h.write(contentsOf: Data("ial\nc\n".utf8))
        try h.close()
        XCTAssertEqual(collect(&r, url, chunk: 2), ["partial", "c"])
        try Data("z\n".utf8).write(to: url)
        XCTAssertEqual(collect(&r, url, chunk: 2), ["z"])
        XCTAssertEqual(collect(&r, URL(fileURLWithPath: "/nonexistent/x.jsonl"), chunk: 2), [])
    }
}

/// Bộ sinh số giả ngẫu nhiên có hạt giống cố định để test lặp lại được.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
