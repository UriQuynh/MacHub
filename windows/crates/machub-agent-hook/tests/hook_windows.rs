// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.
//
// Bản Windows của tests/hook.rs: chạy machub-agent-hook.exe thật qua named pipe thật.
#![cfg(windows)]

use machub_core::wire::{Envelope, EnvelopeKind, PermissionDecision, Reply};
use serde_json::Value;
use std::io::Write;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::windows::named_pipe::ServerOptions;

fn pipe_name() -> String {
    static N: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);
    let n = N.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
    format!(r"\\.\pipe\machub-test-{}-{n}", std::process::id())
}

fn run(pipe: &str, dir: &std::path::Path, stdin: &str) -> (String, i32, Duration) {
    let start = Instant::now();
    let mut child = Command::new(env!("CARGO_BIN_EXE_machub-agent-hook"))
        .arg("claude")
        .env("MACHUB_AGENT_SUPPORT_DIR", dir)
        .env("MACHUB_AGENT_PIPE", pipe)
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

/// Server một lần trên runtime riêng: nhận 1 envelope, trả lời `reply` (None = đóng không trả lời).
fn serve_once(pipe: &str, reply: Option<Option<Value>>, hold: Duration) -> std::thread::JoinHandle<Envelope> {
    let mut server = ServerOptions::new();
    server.first_pipe_instance(true).reject_remote_clients(true);
    let rt = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
    let srv = rt.block_on(async { server.create(pipe) }).unwrap();
    std::thread::spawn(move || {
        rt.block_on(async move {
            srv.connect().await.unwrap();
            let (r, mut w) = tokio::io::split(srv);
            let mut line = String::new();
            BufReader::new(r).read_line(&mut line).await.unwrap();
            let env: Envelope = serde_json::from_str(&line).unwrap();
            if let Some(out) = reply {
                let mut data = serde_json::to_vec(&Reply { output: out }).unwrap();
                data.push(b'\n');
                w.write_all(&data).await.unwrap();
                w.flush().await.unwrap();
            }
            tokio::time::sleep(hold).await;
            env
        })
    })
}

const PERM: &str = r#"{"hook_event_name":"PermissionRequest","session_id":"s1","tool_name":"Bash","tool_input":{"command":"dir"}}"#;

#[test]
fn without_machub_prints_nothing() {
    let dir = tempfile::tempdir().unwrap();
    let (out, code, t) = run(&pipe_name(), dir.path(), PERM);
    assert_eq!((out.as_str(), code), ("", 0));
    assert!(t < Duration::from_secs(3));
}

#[test]
fn allow_over_named_pipe() {
    let dir = tempfile::tempdir().unwrap();
    let pipe = pipe_name();
    let h = serve_once(&pipe, Some(PermissionDecision::Allow.hook_output()), Duration::ZERO);
    let (out, code, _) = run(&pipe, dir.path(), PERM);
    let env = h.join().unwrap();
    assert!(env.wants_reply);
    assert_eq!(env.kind, EnvelopeKind::ClaudeHook);
    assert_eq!(code, 0);
    let v: Value = serde_json::from_str(out.trim()).unwrap();
    assert_eq!(v, PermissionDecision::Allow.hook_output().unwrap());
}

#[test]
fn closing_without_reply_prints_nothing() {
    let dir = tempfile::tempdir().unwrap();
    let pipe = pipe_name();
    let h = serve_once(&pipe, None, Duration::ZERO);
    assert_eq!(run(&pipe, dir.path(), PERM).0, "");
    h.join().unwrap();
}

#[test]
fn observed_events_do_not_wait() {
    let dir = tempfile::tempdir().unwrap();
    let pipe = pipe_name();
    let h = serve_once(&pipe, None, Duration::from_secs(3));
    let (out, code, t) = run(&pipe, dir.path(), r#"{"hook_event_name":"Stop","session_id":"s1"}"#);
    assert_eq!((out.as_str(), code), ("", 0));
    assert!(t < Duration::from_secs(2), "hook quan sát không được chờ app");
    assert!(!h.join().unwrap().wants_reply);
}
