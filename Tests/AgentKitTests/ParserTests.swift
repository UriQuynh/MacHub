// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import XCTest
@testable import AgentKit

final class ClaudeParserTests: XCTestCase {
    func testAssistantUsageLineBecomesRecord() throws {
        let line = JSONValue.parse(#"""
        {"type":"assistant","timestamp":"2026-11-18T10:00:00.123Z","sessionId":"s1","cwd":"/Users/u/FTL_NTL","requestId":"req_1",
         "message":{"id":"msg_1","model":"claude-sonnet-5-5","usage":{"input_tokens":12,"output_tokens":340,
         "cache_creation_input_tokens":1000,"cache_read_input_tokens":20000,
         "cache_creation":{"ephemeral_5m_input_tokens":600,"ephemeral_1h_input_tokens":400}}}}
        """#)!
        let r = try XCTUnwrap(ClaudeTranscript.usageRecord(from: line))
        XCTAssertEqual(r.provider, .claude)
        XCTAssertEqual(r.model, "claude-sonnet-5-5")
        XCTAssertEqual(r.inputTokens, 12)
        XCTAssertEqual(r.outputTokens, 340)
        XCTAssertEqual(r.cacheReadTokens, 20000)
        XCTAssertEqual(r.cacheWrite5mTokens, 600, "Tách theo cache_creation khi có")
        XCTAssertEqual(r.cacheWrite1hTokens, 400)
        XCTAssertEqual(r.project, "/Users/u/FTL_NTL")
        XCTAssertEqual(ClaudeTranscript.dedupeKey(line), "msg_1:req_1")
    }

    func testNonAssistantAndSyntheticLinesAreIgnored() {
        XCTAssertNil(ClaudeTranscript.usageRecord(from: JSONValue.parse(#"{"type":"user","message":{"content":"hi"}}"#)!))
        XCTAssertNil(ClaudeTranscript.usageRecord(from: JSONValue.parse(#"""
        {"type":"assistant","timestamp":"2026-11-18T10:00:00Z","message":{"id":"m","model":"<synthetic>","usage":{"input_tokens":1,"output_tokens":1}}}
        """#)!))
    }

    func testLastModelFromTranscriptTail() {
        let tail = """
        {"type":"assistant","message":{"model":"claude-haiku-4-5"}}
        {"type":"user","message":{}}
        {"type":"assistant","message":{"model":"claude-opus-5-5"}}
        {"type":"assistant","message":{"model":"<synthetic>"}}
        """
        XCTAssertEqual(ClaudeTranscript.lastModel(inTail: tail), "claude-opus-5-5")
    }

    func testOAuthUsageParsesAllWindowsAndSorts() throws {
        let data = Data(#"""
        {"five_hour":{"utilization":7.0,"resets_at":"2026-11-19T05:00:00+00:00"},
         "seven_day":{"utilization":28,"resets_at":"2026-11-23T14:00:00.000Z"},
         "seven_day_fable":{"utilization":0,"resets_at":null},
         "seven_day_opus":null, "extra_usage":{"is_enabled":false}}
        """#.utf8)
        let snap = try XCTUnwrap(ClaudeOAuthUsage.parse(data))
        XCTAssertEqual(snap.windows.map(\.id), ["five_hour", "seven_day", "seven_day_fable"])
        XCTAssertEqual(snap.windows.map(\.label), ["5H", "7D", "7D Fable"])
        XCTAssertEqual(snap.windows[1].usedPercent, 28)
        XCTAssertNotNil(snap.windows[0].resetsAt)
        XCTAssertNil(snap.windows[2].resetsAt)
        XCTAssertEqual(snap.headline?.id, "seven_day")
    }

    func testStatusLinePayload() throws {
        let p = JSONValue.parse(#"""
        {"session_id":"abc","model":{"id":"claude-sonnet-5-5","display_name":"Sonnet 5.5"},
         "workspace":{"current_dir":"/tmp/x"},"context_window":{"used_percentage":41.6},
         "rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1795000000},
                        "seven_day":{"used_percentage":41.2,"resets_at":1795400000}}}
        """#)!
        let sl = ClaudeStatusLine(payload: p)
        XCTAssertEqual(sl.sessionID, "abc")
        XCTAssertEqual(sl.modelID, "claude-sonnet-5-5")
        let limits = try XCTUnwrap(sl.limits)
        XCTAssertEqual(limits.source, .statusLine)
        XCTAssertEqual(limits.windows.map(\.label), ["5H", "7D"])
        XCTAssertEqual(limits.windows[0].resetsAt, Date(timeIntervalSince1970: 1_795_000_000))
        XCTAssertEqual(sl.defaultLine, "Sonnet 5.5 · 5H 24% · 7D 41% · ctx 42%")
    }

    func testStatusLineWithoutRateLimits() {
        let sl = ClaudeStatusLine(payload: JSONValue.parse(#"{"model":{"display_name":"Opus"}}"#)!)
        XCTAssertNil(sl.limits)
        XCTAssertEqual(sl.defaultLine, "Opus")
    }
}

final class CodexParserTests: XCTestCase {
    let rollout = [
        #"{"timestamp":"2026-11-18T09:00:00.000Z","type":"session_meta","payload":{"id":"cx-1","timestamp":"2026-11-18T09:00:00.000Z","cwd":"/Users/u/MacHub","git":{"branch":"agent-monitor"}}}"#,
        #"{"timestamp":"2026-11-18T09:00:01.000Z","type":"turn_context","payload":{"cwd":"/Users/u/MacHub","model":"gpt-5.3-codex"}}"#,
        #"{"timestamp":"2026-11-18T09:00:02.000Z","type":"event_msg","payload":{"type":"task_started"}}"#,
        #"{"timestamp":"2026-11-18T09:00:02.500Z","type":"event_msg","payload":{"type":"user_message","message":"viết test"}}"#,
        #"{"timestamp":"2026-11-18T09:00:10.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":600,"output_tokens":200,"total_tokens":1200},"last_token_usage":{"input_tokens":1000,"cached_input_tokens":600,"output_tokens":200,"total_tokens":1200}},"rate_limits":{"primary":{"used_percent":4.0,"window_minutes":300,"resets_at":1795000000},"secondary":{"used_percent":13.0,"window_minutes":10080,"resets_in_seconds":3600},"plan_type":"pro"}}}"#,
        // token_count lặp lại (không tăng) → không được tính hai lần
        #"{"timestamp":"2026-11-18T09:00:10.100Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":1200},"last_token_usage":{"input_tokens":1000,"cached_input_tokens":600,"output_tokens":200}},"rate_limits":null}}"#,
        #"{"timestamp":"2026-11-18T09:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":1500},"last_token_usage":{"input_tokens":250,"cached_input_tokens":0,"output_tokens":50}}}}"#,
        #"{"timestamp":"2026-11-18T09:01:05.000Z","type":"event_msg","payload":{"type":"task_complete","last_agent_message":"Xong 12 test"}}"#,
    ]

    func testAccumulatesSessionTokensAndLimits() throws {
        var acc = CodexRolloutAccumulator()
        rollout.forEach { acc.consume(line: $0) }
        XCTAssertEqual(acc.sessionID, "cx-1")
        XCTAssertEqual(acc.branch, "agent-monitor")
        XCTAssertEqual(acc.model, "gpt-5.3-codex")
        XCTAssertEqual(acc.state, .finished)
        XCTAssertEqual(acc.lastUserMessage, "viết test")
        XCTAssertEqual(acc.lastAgentMessage, "Xong 12 test")
        XCTAssertEqual(acc.totalTokens, 1500)

        let records = acc.drainRecords()
        XCTAssertEqual(records.count, 2, "token_count lặp lại không được tính")
        XCTAssertEqual(records[0].inputTokens, 400, "input không gồm phần cached")
        XCTAssertEqual(records[0].cacheReadTokens, 600)
        XCTAssertEqual(records[0].outputTokens, 200)
        XCTAssertEqual(records[1].inputTokens, 250)
        XCTAssertTrue(acc.drainRecords().isEmpty)

        let limits = try XCTUnwrap(acc.limits)
        XCTAssertEqual(limits.plan, "pro")
        XCTAssertEqual(limits.windows.map(\.label), ["5H", "7D"])
        XCTAssertEqual(limits.windows[0].resetsAt, Date(timeIntervalSince1970: 1_795_000_000))
        let ts = try XCTUnwrap(ISODate.parse("2026-11-18T09:00:10.000Z"))
        XCTAssertEqual(limits.windows[1].resetsAt, ts.addingTimeInterval(3600), "resets_in_seconds tính từ thời điểm sự kiện")
    }

    func testRunningUntilTaskComplete() {
        var acc = CodexRolloutAccumulator()
        rollout.prefix(4).forEach { acc.consume(line: $0) }
        XCTAssertEqual(acc.state, .running)
    }

    func testGarbageLinesAreSkipped() {
        var acc = CodexRolloutAccumulator()
        acc.consume(line: "not json")
        acc.consume(line: #"{"type":"event_msg"}"#)
        XCTAssertNil(acc.sessionID)
        XCTAssertTrue(acc.drainRecords().isEmpty)
    }

    func testIncrementalReaderKeepsPartialLine() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mh-reader-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("a\nb\npart".utf8).write(to: url)
        var r = IncrementalLineReader()
        XCTAssertEqual(r.readNewLines(at: url), ["a", "b"])
        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd()
        try h.write(contentsOf: Data("ial\nc\n".utf8))
        try h.close()
        XCTAssertEqual(r.readNewLines(at: url), ["partial", "c"])
        XCTAssertEqual(r.readNewLines(at: url), [])
        // File bị ghi đè ngắn hơn → đọc lại từ đầu.
        try Data("z\n".utf8).write(to: url)
        XCTAssertEqual(r.readNewLines(at: url), ["z"])
    }
}

final class PricingTests: XCTestCase {
    let book = PriceBook()

    func testNormalize() {
        XCTAssertEqual(PriceBook.normalize("claude-sonnet-4-20250514"), "sonnet-4")
        XCTAssertEqual(PriceBook.normalize("claude-opus-4-5-20251101"), "opus-4-5")
        XCTAssertEqual(PriceBook.normalize("claude-sonnet-5-5[1m]"), "sonnet-5-5")
    }

    func testExactMatchDoesNotLeakAcrossVersions() throws {
        let opus45 = try XCTUnwrap(book.price(for: "claude-opus-4-5-20251101"))
        XCTAssertEqual(opus45.0.input, 5)
        XCTAssertFalse(opus45.estimated)

        let opus46 = try XCTUnwrap(book.price(for: "claude-opus-4-6"))
        XCTAssertTrue(opus46.estimated, "opus-4 không được khớp nhầm opus-4-6")

        let gpt55 = try XCTUnwrap(book.price(for: "gpt-5.5"))
        XCTAssertTrue(gpt55.estimated, "gpt-5 không được khớp nhầm gpt-5.5")

        let max = try XCTUnwrap(book.price(for: "gpt-5.1-codex-max"))
        XCTAssertFalse(max.estimated)
        XCTAssertEqual(max.0.output, 10)
    }

    func testUnknownModelHasNoPrice() {
        XCTAssertNil(book.price(for: "claude-fable-5-2"))
        let q = book.quote(UsageRecord(provider: .claude, timestamp: Date(), model: "claude-fable-5-2", inputTokens: 10, outputTokens: 10))
        XCTAssertNil(q.usd)
    }

    func testClaudeCostIncludesCacheMultipliers() {
        // sonnet-4: input 3, output 15 → cache 5m 3.75, 1h 6, read 0.3 (USD / 1M)
        let r = UsageRecord(provider: .claude, timestamp: Date(), model: "claude-sonnet-4-20250514",
                            inputTokens: 1_000_000, outputTokens: 1_000_000, cacheWrite5mTokens: 1_000_000,
                            cacheWrite1hTokens: 1_000_000, cacheReadTokens: 1_000_000)
        XCTAssertEqual(book.quote(r).usd!, 3 + 15 + 3.75 + 6 + 0.3, accuracy: 1e-9)
    }

    func testCodexUsesCachedInputPrice() {
        let r = UsageRecord(provider: .codex, timestamp: Date(), model: "gpt-5.3-codex",
                            inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 1_000_000)
        XCTAssertEqual(book.quote(r).usd!, 1.75 + 0.175, accuracy: 1e-9)
    }

    func testUserOverrides() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mh-pricing-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"models":{"claude-fable-5-2":{"input":10,"output":50}}}"#.utf8).write(to: url)
        var b = PriceBook()
        b.applyOverrides(from: url)
        let p = try XCTUnwrap(b.price(for: "claude-fable-5-2"))
        XCTAssertEqual(p.0.output, 50)
        XCTAssertFalse(p.estimated)
    }
}

final class SummaryTests: XCTestCase {
    func testBuildsTotalsByProviderModelProjectAndDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        let day1 = cal.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 10))!
        let day2 = cal.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 23))!
        let records = [
            UsageRecord(provider: .claude, timestamp: day1, model: "claude-sonnet-4", project: "/a/FTL", inputTokens: 100, outputTokens: 10),
            UsageRecord(provider: .claude, timestamp: day2, model: "claude-sonnet-4", project: "/a/FTL", inputTokens: 100, outputTokens: 10),
            UsageRecord(provider: .codex, timestamp: day2, model: "gpt-5.3-codex", project: "/a/MacHub", inputTokens: 50, outputTokens: 5),
            UsageRecord(provider: .claude, timestamp: day1, model: "claude-fable-5-2", project: "/a/X", inputTokens: 7, outputTokens: 0),
        ]
        let s = UsageSummary.build(records: records, from: cal.startOfDay(for: day1), to: day2, prices: PriceBook(), calendar: cal)
        XCTAssertEqual(s.byProvider[.claude]?.total, 227)
        XCTAssertEqual(s.byProvider[.codex]?.total, 55)
        XCTAssertEqual(s.byProvider[.claude]?.unpricedTokens, 7)
        XCTAssertEqual(s.byModel.first?.name, "claude-sonnet-4")
        XCTAssertEqual(s.byProject.first?.name, "FTL")
        XCTAssertEqual(s.days.count, 2)
        XCTAssertEqual(s.days[1].tokens[.codex], 55)
        XCTAssertEqual(s.overall.requests, 4)
    }

    func testFormatting() {
        XCTAssertEqual(UsageFormat.tokens(950), "950")
        XCTAssertEqual(UsageFormat.tokens(1_234), "1,2K")
        XCTAssertEqual(UsageFormat.tokens(3_400_000), "3,4M")
        XCTAssertEqual(UsageFormat.tokens(120_000), "120K")
        XCTAssertEqual(UsageFormat.usd(12.5), "$12,50")
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(UsageFormat.countdown(to: now.addingTimeInterval(3 * 3600 + 9 * 60), now: now), "3g 9ph")
        XCTAssertEqual(UsageFormat.countdown(to: now.addingTimeInterval(4 * 86400 + 13 * 3600), now: now), "4ngày 13g")
        XCTAssertEqual(UsageFormat.countdown(to: now.addingTimeInterval(-5), now: now), "đã reset")
        XCTAssertEqual(UsageFormat.elapsed(since: now.addingTimeInterval(-14 * 60), now: now), "14m")
    }
}
