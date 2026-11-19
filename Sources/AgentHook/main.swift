// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.
//
// machub-agent-hook — Claude Code gọi chương trình này qua hook / statusLine.
//
//   machub-agent-hook claude       (hook: đọc JSON sự kiện từ stdin, gửi cho MacHub)
//   machub-agent-hook statusline   (statusLine: gửi hạn mức cho MacHub, rồi in dòng trạng thái)
//
// Quy tắc an toàn: LUÔN thoát mã 0 và không in gì ra stderr, để Claude Code không bao giờ bị
// chặn hay báo lỗi vì MacHub. Với yêu cầu quyền, nếu MacHub không chạy / không trả lời kịp,
// chương trình KHÔNG in gì → Claude Code tự hỏi trong terminal như bình thường.

import AgentKit
import Foundation

let maxStdin = 4 * 1024 * 1024

func readStdin() -> Data {
    var data = Data()
    while data.count < maxStdin {
        let chunk = FileHandle.standardInput.availableData
        if chunk.isEmpty { break }
        data.append(chunk)
    }
    return data
}

func send(_ envelope: AgentEnvelope, wait: Bool, timeout: TimeInterval) -> UnixSocketClient.Result {
    guard let body = try? AgentCoding.encoder().encode(envelope) else { return .notRunning }
    return UnixSocketClient.send(body, to: AgentPaths.socketURL.path, waitReply: wait, timeout: timeout)
}

func runClaudeHook() {
    let input = readStdin()
    guard let payload = JSONValue.parse(input) else { return }
    let event = payload["hook_event_name"]?.string ?? ""

    if event == "PermissionRequest" {
        let cfg = AgentHookConfig.load()
        let timeout = max(5, min(cfg.approvalTimeoutSeconds, 590))
        let result = send(AgentEnvelope(kind: .claudeHook, payload: payload, wantsReply: true), wait: true, timeout: timeout)
        guard case .reply(let data) = result,
              let reply = try? AgentCoding.decoder().decode(AgentReply.self, from: data),
              let output = reply.output,
              output.path("hookSpecificOutput", "hookEventName")?.string == "PermissionRequest" else { return }
        FileHandle.standardOutput.write(output.encoded())
        FileHandle.standardOutput.write(Data("\n".utf8))
        return
    }
    _ = send(AgentEnvelope(kind: .claudeHook, payload: payload, wantsReply: false), wait: false, timeout: 1)
}

func runStatusLine() {
    let input = readStdin()
    let payload = JSONValue.parse(input) ?? .object([:])
    _ = send(AgentEnvelope(kind: .claudeStatusLine, payload: payload, wantsReply: false), wait: false, timeout: 0.5)

    // Chạy tiếp statusLine cũ của người dùng (nếu có) với cùng stdin.
    let cfg = AgentHookConfig.load()
    if let cmd = cfg.previousStatusLineCommand, !cmd.isEmpty, !cmd.contains(ClaudeSettingsInstaller.marker) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", cmd]
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            inPipe.fileHandleForWriting.write(input)
            try? inPipe.fileHandleForWriting.close()
            let out = outPipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            FileHandle.standardOutput.write(out)
            return
        } catch {
            // rơi xuống dòng mặc định
        }
    }
    let line = ClaudeStatusLine(payload: payload).defaultLine
    FileHandle.standardOutput.write(Data((line.isEmpty ? "MacHub" : line).utf8))
    FileHandle.standardOutput.write(Data("\n".utf8))
}

signal(SIGPIPE, SIG_IGN)
switch CommandLine.arguments.dropFirst().first {
case "claude": runClaudeHook()
case "statusline": runStatusLine()
case "--version": print("machub-agent-hook 1")
default: break
}
exit(0)
