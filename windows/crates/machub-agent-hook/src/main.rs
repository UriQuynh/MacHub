// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.
//
// machub-agent-hook.exe — Claude Code gọi qua hook / statusLine (bản Windows).
//
//   machub-agent-hook claude       hook: đọc JSON sự kiện từ stdin, gửi cho MacHub qua named pipe
//   machub-agent-hook statusline   statusLine: gửi hạn mức cho MacHub rồi in dòng trạng thái
//
// Quy tắc an toàn (giống bản macOS): LUÔN thoát mã 0, không in ra stderr. Với PermissionRequest,
// chỉ in quyết định khi MacHub trả lời rõ ràng; MacHub tắt / hết giờ / trả lời lạ → không in gì,
// Claude Code tự hỏi trong terminal. Không bao giờ tự cho phép.

use machub_core::claude::StatusLine;
use machub_core::installer::{HookConfig, MARKER};
use machub_core::paths;
use machub_core::wire::{is_permission_output, Envelope, EnvelopeKind, Reply};
use serde_json::Value;
use std::io::{Read, Write};
use std::process::{Command, Stdio};
use std::time::Duration;

const MAX_STDIN: u64 = 4 * 1024 * 1024;

fn read_stdin() -> Vec<u8> {
    let mut buf = Vec::new();
    let _ = std::io::stdin().take(MAX_STDIN).read_to_end(&mut buf);
    buf
}

#[derive(Debug, PartialEq)]
enum SendResult {
    NotRunning,
    Sent,
    Reply(Vec<u8>),
    NoReply,
}

fn send(envelope: &Envelope, wait: bool, timeout: Duration) -> SendResult {
    let Ok(mut line) = serde_json::to_vec(envelope) else { return SendResult::NotRunning };
    line.push(b'\n');
    transport::send(&paths::pipe_name(), &line, wait, timeout)
}

fn parent_pid() -> u32 {
    #[cfg(unix)]
    {
        std::os::unix::process::parent_id()
    }
    #[cfg(not(unix))]
    {
        0
    }
}

fn run_claude_hook() {
    let input = read_stdin();
    let Ok(payload) = serde_json::from_slice::<Value>(&input) else { return };
    let event = payload.get("hook_event_name").and_then(Value::as_str).unwrap_or("");

    if event == "PermissionRequest" {
        let cfg = HookConfig::load(&paths::hook_config());
        let timeout = Duration::from_secs_f64(cfg.approval_timeout_seconds.clamp(5.0, 590.0));
        let env = Envelope::new(EnvelopeKind::ClaudeHook, payload, true, parent_pid());
        if let SendResult::Reply(data) = send(&env, true, timeout) {
            if let Ok(reply) = serde_json::from_slice::<Reply>(&data) {
                if let Some(out) = reply.output.filter(is_permission_output) {
                    let mut stdout = std::io::stdout();
                    let _ = writeln!(stdout, "{out}");
                    let _ = stdout.flush();
                }
            }
        }
        return;
    }
    let env = Envelope::new(EnvelopeKind::ClaudeHook, payload, false, parent_pid());
    let _ = send(&env, false, Duration::from_secs(1));
}

fn run_previous_status_line(cmd: &str, input: &[u8]) -> Option<Vec<u8>> {
    // Claude Code trên Windows chạy lệnh qua Git Bash; thử bash trước, rồi tới cmd.
    let shells: [(&str, &str); 2] = [("bash", "-c"), ("cmd", "/C")];
    for (shell, flag) in shells {
        let mut c = Command::new(shell);
        c.arg(flag).arg(cmd).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null());
        #[cfg(windows)]
        {
            use std::os::windows::process::CommandExt;
            c.creation_flags(0x0800_0000); // CREATE_NO_WINDOW: không bật cửa sổ console
        }
        let Ok(mut child) = c.spawn() else { continue };
        if let Some(mut stdin) = child.stdin.take() {
            let _ = stdin.write_all(input);
        }
        if let Ok(out) = child.wait_with_output() {
            return Some(out.stdout);
        }
    }
    None
}

fn run_status_line() {
    let input = read_stdin();
    let payload: Value = serde_json::from_slice(&input).unwrap_or_else(|_| Value::Object(Default::default()));
    let env = Envelope::new(EnvelopeKind::ClaudeStatusLine, payload.clone(), false, parent_pid());
    let _ = send(&env, false, Duration::from_millis(500));

    let mut stdout = std::io::stdout();
    let cfg = HookConfig::load(&paths::hook_config());
    if let Some(cmd) = cfg.previous_command().filter(|c| !c.is_empty() && !c.contains(MARKER)) {
        if let Some(out) = run_previous_status_line(&cmd, &input) {
            let _ = stdout.write_all(&out);
            return;
        }
    }
    let line = StatusLine::parse(&payload, chrono::Utc::now()).default_line();
    let _ = writeln!(stdout, "{}", if line.is_empty() { "MacHub" } else { &line });
}

mod transport {
    use super::SendResult;
    use std::io::{BufRead, BufReader, Write};
    use std::time::Duration;

    #[cfg(windows)]
    pub fn send(pipe: &str, line: &[u8], wait: bool, timeout: Duration) -> SendResult {
        use std::fs::OpenOptions;
        // Pipe đang bận (app đang phục vụ hook khác) → thử lại ngắn.
        let mut file = None;
        for _ in 0..20 {
            match OpenOptions::new().read(true).write(true).open(pipe) {
                Ok(f) => {
                    file = Some(f);
                    break;
                }
                Err(e) if e.raw_os_error() == Some(231) => std::thread::sleep(Duration::from_millis(50)), // ERROR_PIPE_BUSY
                Err(_) => return SendResult::NotRunning,
            }
        }
        let Some(mut f) = file else { return SendResult::NotRunning };
        // Tên pipe là toàn cục: tài khoản khác trên cùng máy có thể chiếm trước tên này.
        // Chỉ nói chuyện với server chạy dưới đúng tài khoản của mình.
        if !server_is_same_user(&f) {
            return SendResult::NotRunning;
        }
        if f.write_all(line).is_err() || f.flush().is_err() {
            return SendResult::NotRunning;
        }
        if !wait {
            return SendResult::Sent;
        }
        read_line_with_timeout(f, timeout)
    }

    #[cfg(windows)]
    fn server_is_same_user(f: &std::fs::File) -> bool {
        use std::os::windows::io::AsRawHandle;
        use windows::Win32::Foundation::{CloseHandle, HANDLE};
        use windows::Win32::Security::{EqualSid, GetTokenInformation, TokenUser, TOKEN_QUERY, TOKEN_USER};
        use windows::Win32::System::Pipes::GetNamedPipeServerProcessId;
        use windows::Win32::System::Threading::{GetCurrentProcess, OpenProcess, OpenProcessToken, PROCESS_QUERY_LIMITED_INFORMATION};

        fn token_user(process: HANDLE) -> Option<Vec<u8>> {
            unsafe {
                let mut tok = HANDLE::default();
                OpenProcessToken(process, TOKEN_QUERY, &mut tok).ok()?;
                let mut len = 0u32;
                let _ = GetTokenInformation(tok, TokenUser, None, 0, &mut len);
                let mut buf = vec![0u8; len as usize];
                let ok = GetTokenInformation(tok, TokenUser, Some(buf.as_mut_ptr() as *mut _), len, &mut len).is_ok();
                let _ = CloseHandle(tok);
                ok.then_some(buf)
            }
        }
        unsafe {
            let mut pid = 0u32;
            if GetNamedPipeServerProcessId(HANDLE(f.as_raw_handle()), &mut pid).is_err() || pid == 0 {
                return false;
            }
            let Ok(proc_) = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) else { return false };
            let server = token_user(proc_);
            let _ = CloseHandle(proc_);
            let (Some(server), Some(me)) = (server, token_user(GetCurrentProcess())) else { return false };
            let a = &*(server.as_ptr() as *const TOKEN_USER);
            let b = &*(me.as_ptr() as *const TOKEN_USER);
            EqualSid(a.User.Sid, b.User.Sid).is_ok()
        }
    }

    #[cfg(unix)]
    pub fn send(pipe: &str, line: &[u8], wait: bool, timeout: Duration) -> SendResult {
        use std::os::unix::net::UnixStream;
        let Ok(mut s) = UnixStream::connect(pipe) else { return SendResult::NotRunning };
        if s.write_all(line).is_err() {
            return SendResult::NotRunning;
        }
        if !wait {
            return SendResult::Sent;
        }
        read_line_with_timeout(s, timeout)
    }

    /// Đọc một dòng trả lời trong thời hạn; quá hạn → NoReply (tiến trình thoát sẽ đóng kết nối).
    fn read_line_with_timeout<R: std::io::Read + Send + 'static>(r: R, timeout: Duration) -> SendResult {
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            let mut reader = BufReader::new(r);
            let mut buf = Vec::new();
            let ok = reader.read_until(b'\n', &mut buf).map(|n| n > 0).unwrap_or(false);
            let _ = tx.send(if ok && buf.ends_with(b"\n") { Some(buf) } else { None });
        });
        match rx.recv_timeout(timeout) {
            Ok(Some(mut buf)) => {
                buf.pop();
                SendResult::Reply(buf)
            }
            _ => SendResult::NoReply,
        }
    }
}

fn main() {
    match std::env::args().nth(1).as_deref() {
        Some("claude") => run_claude_hook(),
        Some("statusline") => run_status_line(),
        Some("--version") => println!("machub-agent-hook 1"),
        _ => {}
    }
    // Không để stdout chưa xả bị mất khi thoát.
    let _ = std::io::stdout().flush();
    std::process::exit(0);
}
