// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import XCTest
@testable import AgentKit

final class SettingsInstallerTests: XCTestCase {
    let hook = "/Users/u/Library/Application Support/MacHub/bin/machub-agent-hook"

    /// Cấu hình có sẵn của người dùng: hook riêng, statusLine riêng, các khóa khác.
    var userSettings: [String: Any] {
        [
            "model": "sonnet",
            "permissions": ["allow": ["Bash(npm test)"]],
            "statusLine": ["type": "command", "command": "~/.claude/statusline.sh", "padding": 0],
            "hooks": [
                "Stop": [["hooks": [["type": "command", "command": "say done"]]]],
                "PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "./guard.sh"]]]],
            ],
        ]
    }

    func testInstallAddsOurHooksAndKeepsEverythingElse() throws {
        let inst = ClaudeSettingsInstaller(hookPath: hook)
        let (out, previous) = inst.installing(into: userSettings, options: .init())
        XCTAssertEqual(out["model"] as? String, "sonnet")
        XCTAssertNotNil(out["permissions"])

        let hooks = try XCTUnwrap(out["hooks"] as? [String: Any])
        // Hook Stop của người dùng vẫn còn, cộng thêm của MacHub.
        let stop = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        XCTAssertEqual(stop.count, 2)
        XCTAssertEqual(((stop[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String), "say done")
        XCTAssertNotNil(hooks["PreToolUse"])

        for event in ClaudeSettingsInstaller.observedEvents {
            let groups = try XCTUnwrap(hooks[event] as? [[String: Any]], event)
            let ours = groups.compactMap { ($0["hooks"] as? [[String: Any]])?.first }.filter { ($0["command"] as? String)?.contains("machub-agent-hook") == true }
            XCTAssertEqual(ours.count, 1, event)
            XCTAssertEqual(ours[0]["async"] as? Bool, true, "\(event) phải chạy nền")
            XCTAssertEqual(ours[0]["command"] as? String, "\"\(hook)\" claude", "đường dẫn có dấu cách phải được bọc ngoặc kép")
        }

        let perm = try XCTUnwrap((hooks["PermissionRequest"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])
        XCTAssertNil(perm[0]["async"], "PermissionRequest phải đồng bộ để Claude chờ quyết định")
        XCTAssertEqual(perm[0]["timeout"] as? Int, 600)

        let sl = try XCTUnwrap(out["statusLine"] as? [String: Any])
        XCTAssertEqual(sl["command"] as? String, "\"\(hook)\" statusline")
        XCTAssertEqual(sl["padding"] as? Int, 0)
        XCTAssertEqual(previous?["command"] as? String, "~/.claude/statusline.sh")

        let state = ClaudeSettingsInstaller.state(of: out)
        XCTAssertTrue(state.observe && state.approvals && state.statusLine)
    }

    func testInstallIsIdempotentAndKeepsOriginalStatusLine() throws {
        let inst = ClaudeSettingsInstaller(hookPath: hook)
        let (once, prev1) = inst.installing(into: userSettings, options: .init())
        let (twice, prev2) = inst.installing(into: once, options: .init())
        XCTAssertNotNil(prev1)
        XCTAssertNil(prev2, "Cài lại không được ghi đè statusLine cũ đã lưu bằng chính statusLine của MacHub")
        let a = try JSONSerialization.data(withJSONObject: once, options: .sortedKeys)
        let b = try JSONSerialization.data(withJSONObject: twice, options: .sortedKeys)
        XCTAssertEqual(a, b)
    }

    func testUninstallRestoresOriginal() throws {
        let inst = ClaudeSettingsInstaller(hookPath: hook)
        let (installed, prev) = inst.installing(into: userSettings, options: .init())
        let restored = ClaudeSettingsInstaller.uninstalling(from: installed, previousStatusLine: prev)
        let a = try JSONSerialization.data(withJSONObject: userSettings, options: .sortedKeys)
        let b = try JSONSerialization.data(withJSONObject: restored, options: .sortedKeys)
        XCTAssertEqual(String(decoding: a, as: UTF8.self), String(decoding: b, as: UTF8.self))
        XCTAssertFalse(ClaudeSettingsInstaller.state(of: restored).installed)
    }

    func testUninstallFromEmptyRemovesKeys() {
        let inst = ClaudeSettingsInstaller(hookPath: hook)
        let (installed, prev) = inst.installing(into: [:], options: .init())
        XCTAssertNil(prev)
        let restored = ClaudeSettingsInstaller.uninstalling(from: installed, previousStatusLine: prev)
        XCTAssertTrue(restored.isEmpty)
    }

    func testOptionsWithoutApprovalsOrStatusLine() throws {
        let inst = ClaudeSettingsInstaller(hookPath: hook)
        let (out, prev) = inst.installing(into: userSettings, options: .init(observe: true, approvals: false, statusLine: false))
        XCTAssertNil(prev)
        XCTAssertEqual((out["statusLine"] as? [String: Any])?["command"] as? String, "~/.claude/statusline.sh")
        XCTAssertNil((out["hooks"] as? [String: Any])?["PermissionRequest"])
        let s = ClaudeSettingsInstaller.state(of: out)
        XCTAssertTrue(s.observe)
        XCTAssertFalse(s.approvals)
        XCTAssertFalse(s.statusLine)
    }

    func testFileRoundTripRejectsInvalidJSONAndBacksUp() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mh-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")

        try Data("{ not json".utf8).write(to: url)
        XCTAssertThrowsError(try ClaudeSettingsInstaller.load(url))

        try Data(#"{"model":"opus"}"#.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let loaded = try ClaudeSettingsInstaller.load(url)
        let backup = try ClaudeSettingsInstaller.save(loaded.merging(["x": 1]) { a, _ in a }, to: url)
        let b = try XCTUnwrap(backup)
        XCTAssertEqual(try String(contentsOf: b, encoding: .utf8), #"{"model":"opus"}"#)
        XCTAssertEqual(try ClaudeSettingsInstaller.load(url)["x"] as? Int, 1)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int, 0o600)

        XCTAssertTrue(try ClaudeSettingsInstaller.load(dir.appendingPathComponent("missing.json")).isEmpty)
    }
}

final class PermissionDecisionTests: XCTestCase {
    func testAllowDenyAndTerminal() {
        XCTAssertEqual(PermissionDecision.allow.hookOutput?.path("hookSpecificOutput", "decision", "behavior"), "allow")
        XCTAssertEqual(PermissionDecision.allow.hookOutput?.path("hookSpecificOutput", "hookEventName"), "PermissionRequest")
        let deny = PermissionDecision.deny(message: "no").hookOutput
        XCTAssertEqual(deny?.path("hookSpecificOutput", "decision", "behavior"), "deny")
        XCTAssertEqual(deny?.path("hookSpecificOutput", "decision", "message"), "no")
        XCTAssertNil(PermissionDecision.askInTerminal.hookOutput, "Không quyết định = không in gì")
    }

    func testAllowAlwaysPassesOnlyAllowSuggestions() {
        let suggestions: JSONValue = [
            ["type": "addRules", "behavior": "allow", "rules": [["toolName": "Bash", "ruleContent": "npm test"]], "destination": "localSettings"],
            ["type": "addRules", "behavior": "deny", "rules": [], "destination": "localSettings"],
        ]
        let out = PermissionDecision.allowAlways(suggestions: suggestions).hookOutput
        let updated = out?.path("hookSpecificOutput", "decision", "updatedPermissions")?.array
        XCTAssertEqual(updated?.count, 1)
        XCTAssertEqual(updated?.first?["behavior"], "allow")
    }
}

final class SocketTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        // Đường dẫn socket phải ngắn (< 104 byte).
        dir = URL(fileURLWithPath: "/tmp/mh-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testRoundTripReplyAndFireAndForget() throws {
        let path = dir.appendingPathComponent("a.sock").path
        let got = expectation(description: "message")
        got.expectedFulfillmentCount = 2
        let server = UnixSocketServer(path: path) { data, reply in
            let text = String(decoding: data, as: UTF8.self)
            got.fulfill()
            reply.send(text == "ping" ? Data("pong".utf8) : nil)
        }
        try server.start()
        defer { server.stop() }

        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)

        XCTAssertEqual(UnixSocketClient.send(Data("ping".utf8), to: path, waitReply: true, timeout: 5), .reply(Data("pong".utf8)))
        XCTAssertEqual(UnixSocketClient.send(Data("event".utf8), to: path, waitReply: false, timeout: 5), .sent)
        wait(for: [got], timeout: 5)
    }

    func testNotRunningAndNoReply() throws {
        XCTAssertEqual(UnixSocketClient.send(Data("x".utf8), to: dir.appendingPathComponent("none.sock").path, waitReply: true, timeout: 1), .notRunning)

        let path = dir.appendingPathComponent("b.sock").path
        let server = UnixSocketServer(path: path) { _, reply in reply.send(nil) }
        try server.start()
        defer { server.stop() }
        XCTAssertEqual(UnixSocketClient.send(Data("x".utf8), to: path, waitReply: true, timeout: 2), .noReply)
    }

    func testServerSeesClientTimeout() throws {
        let path = dir.appendingPathComponent("c.sock").path
        let closed = expectation(description: "onClose")
        let server = UnixSocketServer(path: path) { _, reply in
            reply.onClose { closed.fulfill() } // không trả lời: chờ client bỏ cuộc
        }
        try server.start()
        defer { server.stop() }
        let started = Date()
        XCTAssertEqual(UnixSocketClient.send(Data("x".utf8), to: path, waitReply: true, timeout: 1), .noReply)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        wait(for: [closed], timeout: 3)
    }
}
