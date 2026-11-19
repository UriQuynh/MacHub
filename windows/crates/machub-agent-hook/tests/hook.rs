// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.
//
// Chạy thật machub-agent-hook như Claude Code sẽ gọi. Trên Linux/macOS kênh là socket Unix
// (cùng giao thức dòng JSON với named pipe trên Windows; CI Windows chạy bài riêng).
#![cfg(unix)]

use machub_core::wire::{Envelope, EnvelopeKind, PermissionDecision, Reply};
use serde_json::{json, Value};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixListener;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

struct Env {
    dir: tempfile::TempDir,
}

impl Env {
    fn new() -> Env {
        Env { dir: tempfile::Builder::new().prefix("mhh").tempdir_in("/tmp").unwrap() }
    }
    fn sock(&self) -> String {
        self.dir.path().join("agent.sock").to_string_lossy().into_owned()
    }
    fn run(&self, mode: &str, stdin: &str) -> (String, i32, Duration) {
        let start = Instant::now();
        let mut child = Command::new(env!("CARGO_BIN_EXE_machub-agent-hook"))
            .arg(mode)
            .env("MACHUB_AGENT_SUPPORT_DIR", self.dir.path())
            .env("MACHUB_AGENT_PIPE", self.sock())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        child.stdin.take().unwrap().write_all(stdin.as_bytes()).unwrap();
        let out = child.wait_with_output().unwrap();
        assert!(out.stderr.is_empty(), "hook không được in ra stderr");
        (String::from_utf8(out.stdout).unwrap(), out.status.code().unwrap(), start.elapsed())
    }
    /// Server một lần: nhận 1 envelope, trả lời bằng `reply` (None = đóng không trả lời).
    fn serve_once(&self, reply: Option<Option<Value>>) -> std::thread::JoinHandle<Envelope> {
        let listener = UnixListener::bind(self.sock()).unwrap();
        std::thread::spawn(move || {
            let (mut s, _) = listener.accept().unwrap();
            let mut line = String::new();
            BufReader::new(s.try_clone().unwrap()).read_line(&mut line).unwrap();
            let env: Envelope = serde_json::from_str(&line).unwrap();
            if let Some(out) = reply {
                let mut r = serde_json::to_vec(&Reply { output: out }).unwrap();
                r.push(b'\n');
                s.write_all(&r).unwrap();
            }
            env
        })
    }
}

const PERM: &str = r#"{"hook_event_name":"PermissionRequest","session_id":"s1","tool_name":"Bash","tool_input":{"command":"rm -rf node_modules"}}"#;

#[test]
fn without_machub_prints_nothing() {
    let e = Env::new();
    let (out, code, t) = e.run("claude", PERM);
    assert_eq!((out.as_str(), code), ("", 0));
    assert!(t < Duration::from_secs(3));
}

#[test]
fn allow_is_printed_for_claude_code() {
    let e = Env::new();
    let h = e.serve_once(Some(PermissionDecision::Allow.hook_output()));
    let (out, code, _) = e.run("claude", PERM);
    let env = h.join().unwrap();
    assert!(env.wants_reply);
    assert_eq!(env.kind, EnvelopeKind::ClaudeHook);
    assert_eq!(env.payload["tool_input"]["command"], "rm -rf node_modules");
    assert_eq!(code, 0);
    let v: Value = serde_json::from_str(out.trim()).unwrap();
    assert_eq!(v, PermissionDecision::Allow.hook_output().unwrap());
}

#[test]
fn terminal_and_malformed_replies_print_nothing() {
    let e = Env::new();
    let h = e.serve_once(Some(None));
    assert_eq!(e.run("claude", PERM).0, "");
    h.join().unwrap();

    let e = Env::new();
    let h = e.serve_once(Some(Some(json!({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}))));
    assert_eq!(e.run("claude", PERM).0, "");
    h.join().unwrap();
}

#[test]
fn server_closing_without_reply_prints_nothing() {
    let e = Env::new();
    let h = e.serve_once(None);
    assert_eq!(e.run("claude", PERM).0, "");
    h.join().unwrap();
}

#[test]
fn observed_events_do_not_wait() {
    let e = Env::new();
    let listener = UnixListener::bind(e.sock()).unwrap();
    let h = std::thread::spawn(move || {
        let (s, _) = listener.accept().unwrap();
        let mut line = String::new();
        BufReader::new(s).read_line(&mut line).unwrap();
        std::thread::sleep(Duration::from_secs(3)); // không trả lời
        serde_json::from_str::<Envelope>(&line).unwrap()
    });
    let (out, code, t) = e.run("claude", r#"{"hook_event_name":"Stop","session_id":"s1","last_assistant_message":"xong"}"#);
    assert_eq!((out.as_str(), code), ("", 0));
    assert!(t < Duration::from_secs(2), "hook quan sát không được chờ app");
    let env = h.join().unwrap();
    assert!(!env.wants_reply);
    assert_eq!(env.payload["last_assistant_message"], "xong");
}

#[test]
fn status_line_default_and_previous_command() {
    let e = Env::new();
    let h = e.serve_once(None);
    let (out, _, _) = e.run("statusline", r#"{"model":{"display_name":"Sonnet 5.5"},"rate_limits":{"five_hour":{"used_percentage":7,"resets_at":1795000000}}}"#);
    assert_eq!(out, "Sonnet 5.5 · 5H 7%\n");
    assert_eq!(h.join().unwrap().kind, EnvelopeKind::ClaudeStatusLine);

    let e = Env::new();
    std::fs::write(e.dir.path().join("agent-hook.json"), r#"{"previousStatusLine":{"type":"command","command":"cat"}}"#).unwrap();
    let input = r#"{"model":{"display_name":"Opus"}}"#;
    assert_eq!(e.run("statusline", input).0, input);
}

#[test]
fn garbage_is_harmless() {
    let e = Env::new();
    assert_eq!(e.run("claude", "not json").1, 0);
    assert_eq!(e.run("weird", "").1, 0);
}
