// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import XCTest
@testable import AgentKit

/// Chạy thật chương trình `machub-agent-hook` (do SwiftPM build) như Claude Code sẽ gọi.
final class HookBinaryTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: "/tmp/mhh-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    var hookURL: URL {
        Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("machub-agent-hook")
    }

    struct Run {
        var stdout: String
        var status: Int32
        var seconds: TimeInterval
    }

    func run(_ mode: String, stdin: String) throws -> Run {
        let p = Process()
        p.executableURL = hookURL
        p.arguments = [mode]
        var env = ProcessInfo.processInfo.environment
        env["MACHUB_AGENT_SUPPORT_DIR"] = dir.path
        p.environment = env
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        let start = Date()
        try p.run()
        inPipe.fileHandleForWriting.write(Data(stdin.utf8))
        try inPipe.fileHandleForWriting.close()
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Run(stdout: String(decoding: out, as: UTF8.self), status: p.terminationStatus, seconds: Date().timeIntervalSince(start))
    }

    func startServer(_ handler: @escaping (AgentEnvelope, UnixSocketServer.Reply) -> Void) throws -> UnixSocketServer {
        let server = UnixSocketServer(path: dir.appendingPathComponent("agent.sock").path) { data, reply in
            guard let env = try? AgentCoding.decoder().decode(AgentEnvelope.self, from: data) else { return reply.send(nil) }
            handler(env, reply)
        }
        try server.start()
        return server
    }

    let permissionRequest = #"{"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"rm -rf node_modules"}}"#

    func testBinaryExists() {
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: hookURL.path), hookURL.path)
    }

    func testWithoutMacHubPrintsNothingAndExitsZero() throws {
        let r = try run("claude", stdin: permissionRequest)
        XCTAssertEqual(r.status, 0)
        XCTAssertEqual(r.stdout, "", "Không có MacHub → để Claude Code tự hỏi trong terminal")
        XCTAssertLessThan(r.seconds, 3)
    }

    func testPermissionAllowIsPrintedForClaudeCode() throws {
        let got = expectation(description: "request")
        let server = try startServer { env, reply in
            XCTAssertTrue(env.wantsReply)
            XCTAssertEqual(env.kind, .claudeHook)
            XCTAssertEqual(env.payload.path("tool_input", "command"), "rm -rf node_modules")
            reply.send(try? AgentCoding.encoder().encode(AgentReply(output: PermissionDecision.allow.hookOutput)))
            got.fulfill()
        }
        defer { server.stop() }
        let r = try run("claude", stdin: permissionRequest)
        wait(for: [got], timeout: 5)
        XCTAssertEqual(r.status, 0)
        let out = try XCTUnwrap(JSONValue.parse(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertEqual(out, PermissionDecision.allow.hookOutput)
    }

    func testDenyAndTerminalDecisions() throws {
        var decisions: [PermissionDecision] = [.deny(message: "không"), .askInTerminal]
        let server = try startServer { _, reply in
            let d = decisions.removeFirst()
            reply.send(try? AgentCoding.encoder().encode(AgentReply(output: d.hookOutput)))
        }
        defer { server.stop() }
        let deny = try run("claude", stdin: permissionRequest)
        XCTAssertEqual(JSONValue.parse(deny.stdout.trimmingCharacters(in: .whitespacesAndNewlines))?.path("hookSpecificOutput", "decision", "behavior"), "deny")
        let terminal = try run("claude", stdin: permissionRequest)
        XCTAssertEqual(terminal.stdout, "")
    }

    func testMalformedReplyIsIgnored() throws {
        let server = try startServer { _, reply in
            // Trả lời không phải cho PermissionRequest → hook không được in ra.
            reply.send(try? AgentCoding.encoder().encode(AgentReply(output: ["hookSpecificOutput": ["hookEventName": "PreToolUse", "permissionDecision": "allow"]])))
        }
        defer { server.stop() }
        XCTAssertEqual(try run("claude", stdin: permissionRequest).stdout, "")
    }

    func testObservedEventIsForwardedWithoutWaiting() throws {
        let got = expectation(description: "event")
        let server = try startServer { env, reply in
            XCTAssertFalse(env.wantsReply)
            XCTAssertEqual(env.payload["hook_event_name"], "Stop")
            XCTAssertEqual(env.payload["last_assistant_message"], "xong")
            got.fulfill()
            // cố tình không trả lời: hook vẫn phải thoát ngay
            _ = reply
        }
        defer { server.stop() }
        let r = try run("claude", stdin: #"{"hook_event_name":"Stop","session_id":"s1","last_assistant_message":"xong"}"#)
        XCTAssertEqual(r.status, 0)
        XCTAssertEqual(r.stdout, "")
        XCTAssertLessThan(r.seconds, 2)
        wait(for: [got], timeout: 5)
    }

    func testStatusLineForwardsAndPrintsDefaultLine() throws {
        let got = expectation(description: "statusline")
        let server = try startServer { env, reply in
            XCTAssertEqual(env.kind, .claudeStatusLine)
            reply.send(nil)
            got.fulfill()
        }
        defer { server.stop() }
        let r = try run("statusline", stdin: #"{"model":{"display_name":"Sonnet 5.5"},"rate_limits":{"five_hour":{"used_percentage":7,"resets_at":1795000000}}}"#)
        wait(for: [got], timeout: 5)
        XCTAssertEqual(r.stdout, "Sonnet 5.5 · 5H 7%\n")
    }

    func testStatusLineRunsPreviousCommandWithSameInput() throws {
        let cfg = AgentHookConfig(previousStatusLine: ["type": "command", "command": "cat"])
        try cfg.save(dir.appendingPathComponent("agent-hook.json"))
        let input = #"{"model":{"display_name":"Opus"}}"#
        let r = try run("statusline", stdin: input)
        XCTAssertEqual(r.stdout, input, "statusLine cũ phải nhận đúng stdin và in ra như trước")
    }

    func testGarbageInputIsHarmless() throws {
        XCTAssertEqual(try run("claude", stdin: "not json").status, 0)
        XCTAssertEqual(try run("unknown-mode", stdin: "").status, 0)
    }
}
