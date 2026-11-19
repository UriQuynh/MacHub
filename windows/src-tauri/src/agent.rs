// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

//! Theo dõi agent trên Windows: phiên Claude Code (qua hook + named pipe), Codex (đọc log),
//! hạn mức, token/chi phí, duyệt quyền. Cùng quy tắc an toàn với bản macOS.

use chrono::{DateTime, Duration as ChronoDuration, Local, Utc};
use machub_core::claude::{self, StatusLine};
use machub_core::codex::{CodexState, RolloutAccumulator};
use machub_core::installer::{self, HookConfig, Installer, Options};
use machub_core::lines::IncrementalLineReader;
use machub_core::pricing::PriceBook;
use machub_core::summary::{self, Summary};
use machub_core::wire::{Envelope, EnvelopeKind, PermissionDecision, Reply};
use machub_core::{paths, LimitSnapshot, LimitWindow, Provider, UsageRecord};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime};
use tauri::{AppHandle, Emitter};
use tokio::sync::oneshot;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum SessionState {
    Idle,
    Running,
    WaitingApproval,
    WaitingInput,
    SubagentDone,
    Finished,
    Ended,
}

impl SessionState {
    fn is_active(self) -> bool {
        matches!(self, Self::Running | Self::WaitingApproval | Self::WaitingInput | Self::SubagentDone)
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Session {
    pub id: String,
    pub provider: Provider,
    pub session_id: String,
    pub title: Option<String>,
    pub cwd: Option<String>,
    pub repo: Option<String>,
    pub branch: Option<String>,
    pub model: Option<String>,
    pub state: SessionState,
    pub active: bool,
    pub last_prompt: Option<String>,
    pub last_message: Option<String>,
    pub started_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub running_subagents: u32,
}

impl Session {
    fn new(provider: Provider, sid: &str, now: DateTime<Utc>) -> Self {
        Session {
            id: format!("{}:{sid}", if provider == Provider::Claude { "claude" } else { "codex" }),
            provider,
            session_id: sid.to_string(),
            title: None,
            cwd: None,
            repo: None,
            branch: None,
            model: None,
            state: SessionState::Idle,
            active: false,
            last_prompt: None,
            last_message: None,
            started_at: now,
            updated_at: now,
            running_subagents: 0,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ApprovalView {
    pub id: u64,
    pub session_key: String,
    pub tool_name: String,
    pub summary: String,
    pub detail: Option<String>,
    pub project: Option<String>,
    pub can_always_allow: bool,
    pub created_at: DateTime<Utc>,
}

struct Pending {
    view: ApprovalView,
    suggestions: Option<Value>,
    tx: Option<oneshot::Sender<Option<Value>>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentSettings {
    pub approvals_enabled: bool,
    pub approval_timeout: f64,
    pub oauth_enabled: bool,
}

impl Default for AgentSettings {
    fn default() -> Self {
        AgentSettings { approvals_enabled: true, approval_timeout: 120.0, oauth_enabled: false }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentView {
    pub sessions: Vec<Session>,
    pub running: usize,
    pub approvals: Vec<ApprovalView>,
    pub claude_limits: Option<LimitSnapshot>,
    pub codex_limits: Option<LimitSnapshot>,
    pub summary: Summary,
    pub range: String,
    pub hook_state: installer::State,
    pub settings: AgentSettings,
    pub oauth_error: Option<String>,
    pub server_error: Option<String>,
    pub setup_message: Option<String>,
}

#[derive(Default)]
struct Scanner {
    claude_files: HashMap<PathBuf, IncrementalLineReader>,
    codex_files: HashMap<PathBuf, (IncrementalLineReader, RolloutAccumulator)>,
    seen: HashSet<String>,
}

#[derive(Default)]
struct Inner {
    claude_sessions: HashMap<String, Session>,
    codex_sessions: Vec<Session>,
    pending: Vec<Pending>,
    next_id: u64,
    records: Vec<UsageRecord>,
    claude_statusline: Option<LimitSnapshot>,
    claude_oauth: Option<LimitSnapshot>,
    codex_limits: Option<LimitSnapshot>,
    settings: AgentSettings,
    range: String,
    oauth_error: Option<String>,
    server_error: Option<String>,
    setup_message: Option<String>,
    visible: bool,
}

#[derive(Clone)]
pub struct Agent {
    inner: Arc<Mutex<Inner>>,
    scanner: Arc<Mutex<Scanner>>,
    prices: Arc<PriceBook>,
    app: AppHandle,
}

fn settings_path() -> PathBuf {
    paths::support_dir().join("agent-settings.json")
}

fn clip(s: &str) -> String {
    let t = s.trim().replace(['\r', '\n'], " ");
    if t.chars().count() > 280 {
        t.chars().take(280).collect::<String>() + "…"
    } else {
        t
    }
}

/// Tên repo + nhánh, đọc thẳng `.git` (không chạy git).
pub fn git_info(cwd: &str) -> (Option<String>, Option<String>) {
    let mut dir = PathBuf::from(cwd);
    for _ in 0..12 {
        let git = dir.join(".git");
        if git.exists() {
            let mut git_dir = git.clone();
            if git.is_file() {
                if let Ok(t) = std::fs::read_to_string(&git) {
                    if let Some(p) = t.lines().find_map(|l| l.strip_prefix("gitdir:")) {
                        let p = PathBuf::from(p.trim());
                        git_dir = if p.is_absolute() { p } else { dir.join(p) };
                    }
                }
            }
            let head = std::fs::read_to_string(git_dir.join("HEAD")).unwrap_or_default();
            let branch = match head.trim().strip_prefix("ref: refs/heads/") {
                Some(b) => Some(b.to_string()),
                None if !head.trim().is_empty() => Some(head.trim().chars().take(7).collect()),
                None => None,
            };
            return (dir.file_name().map(|n| n.to_string_lossy().into_owned()), branch);
        }
        if !dir.pop() {
            break;
        }
    }
    (Path::new(cwd).file_name().map(|n| n.to_string_lossy().into_owned()), None)
}

fn describe_tool(input: Option<&Value>, tool: &str) -> (String, Option<String>) {
    let Some(i) = input else { return (tool.to_string(), None) };
    let s = |k: &str| i.get(k).and_then(Value::as_str).map(str::to_string);
    if let Some(c) = s("command") {
        return (c, s("description"));
    }
    if let Some(p) = s("file_path").or_else(|| s("notebook_path")).or_else(|| s("path")) {
        return (p, None);
    }
    if let Some(u) = s("url") {
        return (u, s("prompt"));
    }
    if let Some(p) = s("pattern") {
        return (p, None);
    }
    let j = i.to_string();
    (if j.len() > 300 { j.chars().take(300).collect::<String>() + "…" } else { j }, None)
}

impl Agent {
    pub fn new(app: AppHandle) -> Agent {
        let mut prices = PriceBook::default();
        prices.apply_overrides(&paths::support_dir().join("pricing.json"));
        let settings: AgentSettings = std::fs::read_to_string(settings_path())
            .ok()
            .and_then(|t| serde_json::from_str(&t).ok())
            .unwrap_or_default();
        let inner = Inner { settings, range: "today".into(), ..Default::default() };
        Agent { inner: Arc::new(Mutex::new(inner)), scanner: Default::default(), prices: Arc::new(prices), app }
    }

    pub fn start(&self) {
        if installer::state(&installer::load(&paths::claude_settings()).unwrap_or_default()).installed {
            let _ = refresh_hook_binary();
        }
        let me = self.clone();
        tauri::async_runtime::spawn(async move { me.serve().await });

        // Quét log: 15 giây khi cửa sổ mở, 60 giây khi chạy nền.
        let me = self.clone();
        std::thread::spawn(move || loop {
            me.scan();
            me.refresh_oauth(false);
            me.prune();
            let visible = me.inner.lock().map(|i| i.visible).unwrap_or(false);
            std::thread::sleep(Duration::from_secs(if visible { 15 } else { 60 }));
        });
    }

    pub fn set_visible(&self, v: bool) {
        if let Ok(mut i) = self.inner.lock() {
            i.visible = v;
        }
        if v {
            let me = self.clone();
            std::thread::spawn(move || {
                me.scan();
                me.notify();
            });
        }
    }

    fn notify(&self) {
        let _ = self.app.emit("agent-updated", ());
    }

    // ───────────── Named pipe ─────────────

    #[cfg(windows)]
    async fn serve(&self) {
        use tokio::net::windows::named_pipe::ServerOptions;
        let name = paths::pipe_name();
        let make = |first: bool| -> std::io::Result<tokio::net::windows::named_pipe::NamedPipeServer> {
            let mut o = ServerOptions::new();
            o.first_pipe_instance(first).reject_remote_clients(true);
            let sa = owner_only_security_attributes();
            match sa {
                Some(mut sa) => unsafe { o.create_with_security_attributes_raw(&name, &mut sa.attrs as *mut _ as *mut std::ffi::c_void) },
                None => o.create(&name),
            }
        };
        let mut server = match make(true) {
            Ok(s) => s,
            Err(e) => {
                // Tên pipe đã bị chiếm (một MacHub khác hoặc tiến trình lạ) → không nhận sự kiện.
                self.set_server_error(format!("Không mở được kênh hook ({e})."));
                return;
            }
        };
        loop {
            if server.connect().await.is_err() {
                continue;
            }
            let client = server;
            server = match make(false) {
                Ok(s) => s,
                Err(e) => {
                    self.set_server_error(format!("Kênh hook lỗi: {e}"));
                    return;
                }
            };
            let me = self.clone();
            tauri::async_runtime::spawn(async move { me.handle_conn(client).await });
        }
    }

    #[cfg(not(windows))]
    async fn serve(&self) {
        use tokio::net::UnixListener;
        let name = paths::pipe_name();
        let _ = std::fs::create_dir_all(paths::support_dir());
        let _ = std::fs::remove_file(&name);
        let Ok(listener) = UnixListener::bind(&name) else { return };
        while let Ok((s, _)) = listener.accept().await {
            let me = self.clone();
            tauri::async_runtime::spawn(async move { me.handle_conn(s).await });
        }
    }

    fn set_server_error(&self, e: String) {
        if let Ok(mut i) = self.inner.lock() {
            i.server_error = Some(e);
        }
        self.notify();
    }

    async fn handle_conn<S>(&self, stream: S)
    where
        S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + Send + 'static,
    {
        use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
        let (r, mut w) = tokio::io::split(stream);
        let mut reader = BufReader::new(r);
        let mut line = Vec::new();
        let read = (&mut reader).take(8 * 1024 * 1024).read_until(b'\n', &mut line).await;
        if !matches!(read, Ok(n) if n > 0) {
            return;
        }
        let Ok(env) = serde_json::from_slice::<Envelope>(&line) else { return };
        match env.kind {
            EnvelopeKind::ClaudeStatusLine => self.on_statusline(&env.payload),
            EnvelopeKind::ClaudeHook => {
                let rx = self.on_hook(&env);
                if let Some((id, rx, timeout)) = rx {
                    let mut probe = [0u8; 1];
                    let output = tokio::select! {
                        r = tokio::time::timeout(timeout, rx) => match r {
                            Ok(Ok(out)) => out,
                            _ => None, // hết giờ: trả về terminal
                        },
                        _ = reader.read(&mut probe) => None, // hook đã đóng kết nối
                    };
                    self.finish_approval(id);
                    let mut data = serde_json::to_vec(&Reply { output }).unwrap_or_default();
                    data.push(b'\n');
                    let _ = w.write_all(&data).await;
                    let _ = w.flush().await;
                }
            }
        }
    }

    fn on_statusline(&self, payload: &Value) {
        let sl = StatusLine::parse(payload, Utc::now());
        if let Ok(mut i) = self.inner.lock() {
            if let Some(l) = sl.limits.clone() {
                i.claude_statusline = Some(l);
            }
            if let Some(sid) = &sl.session_id {
                if let Some(s) = i.claude_sessions.get_mut(&format!("claude:{sid}")) {
                    if let Some(m) = sl.model_id.clone().or(sl.model_name.clone()) {
                        s.model = Some(m);
                    }
                }
            }
        }
        self.notify();
    }

    /// Cập nhật phiên; với PermissionRequest trả về kênh chờ quyết định.
    fn on_hook(&self, env: &Envelope) -> Option<(u64, oneshot::Receiver<Option<Value>>, Duration)> {
        let p = &env.payload;
        let s = |k: &str| p.get(k).and_then(Value::as_str);
        let event = s("hook_event_name").unwrap_or("");
        let sid = s("session_id").unwrap_or("unknown");
        let key = format!("claude:{sid}");
        let now = Utc::now();
        let mut result = None;
        {
            let Ok(mut i) = self.inner.lock() else { return None };
            let sess = i.claude_sessions.entry(key.clone()).or_insert_with(|| Session::new(Provider::Claude, sid, now));
            sess.updated_at = now;
            if let Some(cwd) = s("cwd") {
                if sess.cwd.as_deref() != Some(cwd) {
                    sess.cwd = Some(cwd.into());
                    let (repo, branch) = git_info(cwd);
                    sess.repo = repo;
                    sess.branch = branch;
                }
            }
            if let Some(t) = s("session_title").filter(|t| !t.is_empty()) {
                sess.title = Some(t.into());
            }
            match event {
                "SessionStart" => {
                    sess.state = SessionState::Idle;
                    if let Some(m) = s("model") {
                        sess.model = Some(m.into());
                    }
                }
                "UserPromptSubmit" => {
                    sess.state = SessionState::Running;
                    sess.running_subagents = 0;
                    sess.last_prompt = s("prompt").map(clip);
                }
                "SubagentStart" => {
                    sess.running_subagents += 1;
                    if !sess.state.is_active() {
                        sess.state = SessionState::Running;
                    }
                }
                "SubagentStop" => {
                    sess.running_subagents = sess.running_subagents.saturating_sub(1);
                    if let Some(m) = s("last_assistant_message") {
                        sess.last_message = Some(clip(m));
                    }
                    if matches!(sess.state, SessionState::Running | SessionState::SubagentDone) {
                        sess.state = SessionState::SubagentDone;
                    }
                }
                "Stop" => {
                    sess.state = SessionState::Finished;
                    sess.running_subagents = 0;
                    if let Some(m) = s("last_assistant_message") {
                        sess.last_message = Some(clip(m));
                    }
                    if let Some(path) = s("transcript_path") {
                        if let Some(m) = tail_model(path) {
                            sess.model = Some(m);
                        }
                    }
                }
                "Notification" => match s("notification_type") {
                    Some("permission_prompt") => sess.state = SessionState::WaitingApproval,
                    Some("idle_prompt") | Some("agent_needs_input") | Some("elicitation_dialog") => {
                        sess.state = SessionState::WaitingInput
                    }
                    _ => {}
                },
                "PermissionRequest" => sess.state = SessionState::WaitingApproval,
                "SessionEnd" => {
                    sess.state = SessionState::Ended;
                    sess.running_subagents = 0;
                }
                _ => {}
            }
            sess.active = sess.state.is_active();

            if event == "PermissionRequest" && env.wants_reply && i.settings.approvals_enabled {
                let tool = s("tool_name").unwrap_or("Tool").to_string();
                let (summary, detail) = describe_tool(p.get("tool_input"), &tool);
                let suggestions = p.get("permission_suggestions").filter(|v| v.as_array().is_some_and(|a| !a.is_empty())).cloned();
                i.next_id += 1;
                let id = i.next_id;
                let (tx, rx) = oneshot::channel();
                i.pending.push(Pending {
                    view: ApprovalView {
                        id,
                        session_key: key.clone(),
                        tool_name: tool,
                        summary,
                        detail,
                        project: s("cwd").map(|c| Path::new(c).file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default()),
                        can_always_allow: suggestions.is_some(),
                        created_at: now,
                    },
                    suggestions,
                    tx: Some(tx),
                });
                let timeout = Duration::from_secs_f64(i.settings.approval_timeout.max(10.0));
                result = Some((id, rx, timeout));
            }
        }
        if result.is_some() {
            crate::show_approval_window(&self.app);
        } else if event == "PermissionRequest" && env.wants_reply {
            // Duyệt quyền đang tắt → trả lời ngay "không quyết định".
            let (tx, rx) = oneshot::channel();
            let _ = tx.send(None);
            result = Some((0, rx, Duration::from_secs(1)));
        }
        self.notify();
        result
    }

    pub fn respond(&self, id: u64, decision: &str) -> bool {
        let Ok(mut i) = self.inner.lock() else { return false };
        let Some(p) = i.pending.iter_mut().find(|p| p.view.id == id) else { return false };
        let d = match decision {
            "allow" => PermissionDecision::Allow,
            "always" => PermissionDecision::AllowAlways(p.suggestions.clone().unwrap_or(Value::Null)),
            "deny" => PermissionDecision::Deny("Người dùng từ chối từ MacHub.".into()),
            _ => PermissionDecision::AskInTerminal,
        };
        let sent = p.tx.take().map(|tx| tx.send(d.hook_output()).is_ok()).unwrap_or(false);
        let key = p.view.session_key.clone();
        if sent && matches!(d, PermissionDecision::Allow | PermissionDecision::AllowAlways(_) | PermissionDecision::Deny(_)) {
            if let Some(s) = i.claude_sessions.get_mut(&key) {
                s.state = SessionState::Running;
                s.active = true;
            }
        }
        sent
    }

    fn finish_approval(&self, id: u64) {
        let empty = {
            let Ok(mut i) = self.inner.lock() else { return };
            i.pending.retain(|p| p.view.id != id);
            i.pending.is_empty()
        };
        if empty {
            crate::hide_approval_window(&self.app);
        }
        self.notify();
    }

    // ───────────── Quét log ─────────────

    fn scan(&self) {
        let cutoff = Utc::now() - ChronoDuration::days(31);
        let cutoff_sys = SystemTime::now() - Duration::from_secs(31 * 86_400);
        let mut new_records = Vec::new();
        let mut codex_sessions = Vec::new();
        let mut codex_limits: Option<LimitSnapshot> = None;
        {
            let Ok(mut sc) = self.scanner.lock() else { return };
            let sc = &mut *sc;
            for root in paths::claude_project_dirs() {
                for f in jsonl_files(&root, cutoff_sys, 4) {
                    let reader = sc.claude_files.entry(f.clone()).or_default();
                    for line in reader.read_new_lines(&f, 64 * 1024 * 1024) {
                        if !line.contains("\"usage\"") {
                            continue;
                        }
                        let Ok(v) = serde_json::from_str::<Value>(&line) else { continue };
                        let Some(r) = claude::usage_record(&v) else { continue };
                        if let Some(k) = claude::dedupe_key(&v) {
                            if !sc.seen.insert(k) {
                                continue;
                            }
                        }
                        if r.timestamp >= cutoff {
                            new_records.push(r);
                        }
                    }
                }
            }
            let now = Utc::now();
            for f in jsonl_files(&paths::codex_sessions_dir(), cutoff_sys, 4)
                .into_iter()
                .filter(|p| p.file_name().is_some_and(|n| n.to_string_lossy().starts_with("rollout-")))
            {
                let (reader, acc) = sc.codex_files.entry(f.clone()).or_default();
                for line in reader.read_new_lines(&f, 64 * 1024 * 1024) {
                    acc.consume_line(&line);
                }
                new_records.extend(acc.drain_records().into_iter().filter(|r| r.timestamp >= cutoff));
                if let Some(l) = &acc.limits {
                    if codex_limits.as_ref().is_none_or(|c| l.observed_at > c.observed_at) {
                        codex_limits = Some(l.clone());
                    }
                }
                let Some(last) = acc.last_activity else { continue };
                if now - last > ChronoDuration::hours(12) {
                    continue;
                }
                let sid = acc.session_id.clone().unwrap_or_else(|| f.file_stem().unwrap_or_default().to_string_lossy().into_owned());
                let mut s = Session::new(Provider::Codex, &sid, acc.started_at.unwrap_or(last));
                s.cwd = acc.cwd.clone();
                if let Some(c) = &acc.cwd {
                    let (repo, branch) = git_info(c);
                    s.repo = repo;
                    s.branch = acc.branch.clone().or(branch);
                }
                s.model = acc.model.clone();
                s.last_prompt = acc.last_user_message.as_deref().map(clip);
                s.last_message = acc.last_agent_message.as_deref().map(clip);
                s.updated_at = last;
                s.state = match acc.state {
                    // Codex bị tắt ngang có thể để lại "running": quá 15 phút không ghi gì → coi như xong.
                    CodexState::Running if now - last < ChronoDuration::minutes(15) => SessionState::Running,
                    CodexState::Running | CodexState::Finished => SessionState::Finished,
                    CodexState::Idle => SessionState::Idle,
                };
                s.active = s.state.is_active();
                codex_sessions.push(s);
            }
        }
        if let Ok(mut i) = self.inner.lock() {
            i.records.extend(new_records);
            i.records.retain(|r| r.timestamp >= cutoff);
            i.codex_sessions = codex_sessions;
            if codex_limits.is_some() {
                i.codex_limits = codex_limits;
            }
        }
        self.notify();
    }

    fn prune(&self) {
        let now = Utc::now();
        if let Ok(mut i) = self.inner.lock() {
            i.claude_sessions.retain(|_, s| {
                let age = now - s.updated_at;
                !((s.state == SessionState::Ended && age > ChronoDuration::minutes(30))
                    || (!s.state.is_active() && age > ChronoDuration::hours(12)))
            });
        }
    }

    // ───────────── OAuth (tùy chọn) ─────────────

    pub fn refresh_oauth(&self, force: bool) {
        let enabled = self.inner.lock().map(|i| i.settings.oauth_enabled).unwrap_or(false);
        if !enabled {
            return;
        }
        // 5 phút một lần (vòng quét gọi mỗi 15–60 giây).
        static LAST: Mutex<Option<std::time::Instant>> = Mutex::new(None);
        {
            let mut last = LAST.lock().unwrap_or_else(|e| e.into_inner());
            if !force && last.is_some_and(|t| t.elapsed() < Duration::from_secs(300)) {
                return;
            }
            *last = Some(std::time::Instant::now());
        }
        let result = fetch_oauth_usage();
        if let Ok(mut i) = self.inner.lock() {
            match result {
                Ok(s) => {
                    i.claude_oauth = Some(s);
                    i.oauth_error = None;
                }
                Err(e) => i.oauth_error = Some(e),
            }
        }
        self.notify();
    }

    // ───────────── Xem & cài đặt ─────────────

    pub fn view(&self) -> AgentView {
        let hook_state = installer::state(&installer::load(&paths::claude_settings()).unwrap_or_default());
        let i = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        let mut sessions: Vec<Session> = i.claude_sessions.values().cloned().chain(i.codex_sessions.iter().cloned()).collect();
        sessions.sort_by(|a, b| b.active.cmp(&a.active).then(b.updated_at.cmp(&a.updated_at)));
        let now = Utc::now();
        let today = Local::now().date_naive().and_hms_opt(0, 0, 0).and_then(|d| d.and_local_timezone(Local).single());
        let start = today.map(|d| d.with_timezone(&Utc)).unwrap_or(now)
            - ChronoDuration::days(match i.range.as_str() {
                "week" => 6,
                "month" => 29,
                _ => 0,
            });
        AgentView {
            running: sessions.iter().filter(|s| s.active).count(),
            sessions,
            approvals: i.pending.iter().map(|p| p.view.clone()).collect(),
            claude_limits: merge_limits(i.claude_statusline.as_ref(), i.claude_oauth.as_ref()),
            codex_limits: i.codex_limits.clone(),
            summary: summary::build(&i.records, start, now, &self.prices),
            range: i.range.clone(),
            hook_state,
            settings: i.settings.clone(),
            oauth_error: i.oauth_error.clone(),
            server_error: i.server_error.clone(),
            setup_message: i.setup_message.clone(),
        }
    }

    pub fn set_range(&self, r: &str) {
        if let Ok(mut i) = self.inner.lock() {
            i.range = match r {
                "week" | "month" => r.into(),
                _ => "today".into(),
            };
        }
        self.notify();
    }

    pub fn update_settings(&self, s: AgentSettings) {
        let oauth_turned_on;
        {
            let Ok(mut i) = self.inner.lock() else { return };
            oauth_turned_on = s.oauth_enabled && !i.settings.oauth_enabled;
            if !s.oauth_enabled {
                i.claude_oauth = None;
                i.oauth_error = None;
            }
            i.settings = AgentSettings { approval_timeout: s.approval_timeout.clamp(30.0, 300.0), ..s };
            let _ = std::fs::create_dir_all(paths::support_dir());
            let _ = std::fs::write(settings_path(), serde_json::to_string_pretty(&i.settings).unwrap_or_default());
        }
        let cfg_path = paths::hook_config();
        let mut cfg = HookConfig::load(&cfg_path);
        cfg.approval_timeout_seconds = s.approval_timeout.clamp(30.0, 300.0);
        let _ = cfg.save(&cfg_path);
        if oauth_turned_on {
            let me = self.clone();
            std::thread::spawn(move || me.refresh_oauth(true));
        }
        self.notify();
    }

    pub fn install(&self, status_line: bool) {
        let msg = match install_hooks(status_line, &self.inner.lock().map(|i| i.settings.clone()).unwrap_or_default()) {
            Ok(b) => format!(
                "Đã cài hook. Mở phiên Claude Code mới để bắt đầu theo dõi.{}",
                b.map(|p| format!(" Bản sao lưu: {}", p.file_name().unwrap_or_default().to_string_lossy())).unwrap_or_default()
            ),
            Err(e) => e,
        };
        if let Ok(mut i) = self.inner.lock() {
            i.setup_message = Some(msg);
        }
        self.notify();
    }

    pub fn uninstall(&self) {
        let msg = match uninstall_hooks() {
            Ok(_) => "Đã gỡ hook MacHub khỏi Claude Code.".to_string(),
            Err(e) => e,
        };
        if let Ok(mut i) = self.inner.lock() {
            i.setup_message = Some(msg);
        }
        self.notify();
    }

    pub fn rescan(&self) {
        let me = self.clone();
        std::thread::spawn(move || me.scan());
    }
}

fn merge_limits(a: Option<&LimitSnapshot>, b: Option<&LimitSnapshot>) -> Option<LimitSnapshot> {
    let snaps: Vec<&LimitSnapshot> = [a, b].into_iter().flatten().collect();
    let newest = snaps.iter().max_by_key(|s| s.observed_at)?;
    let mut by_id: HashMap<String, (LimitWindow, DateTime<Utc>)> = HashMap::new();
    for s in &snaps {
        for w in &s.windows {
            if by_id.get(&w.id).is_none_or(|(_, t)| *t < s.observed_at) {
                by_id.insert(w.id.clone(), (w.clone(), s.observed_at));
            }
        }
    }
    let mut windows: Vec<LimitWindow> = by_id.into_values().map(|(w, _)| w).collect();
    claude::sort_windows(&mut windows);
    Some(LimitSnapshot { provider: Provider::Claude, windows, observed_at: newest.observed_at, source: newest.source, plan: None })
}

fn tail_model(path: &str) -> Option<String> {
    use std::io::{Read, Seek, SeekFrom};
    let mut f = std::fs::File::open(path).ok()?;
    let size = f.seek(SeekFrom::End(0)).ok()?;
    f.seek(SeekFrom::Start(size.saturating_sub(65_536))).ok()?;
    let mut buf = Vec::new();
    f.read_to_end(&mut buf).ok()?;
    claude::last_model(&String::from_utf8_lossy(&buf))
}

fn jsonl_files(root: &Path, cutoff: SystemTime, max_depth: usize) -> Vec<PathBuf> {
    fn walk(dir: &Path, depth: usize, max: usize, cutoff: SystemTime, out: &mut Vec<(PathBuf, SystemTime)>) {
        let Ok(rd) = std::fs::read_dir(dir) else { return };
        for e in rd.flatten() {
            let Ok(ft) = e.file_type() else { continue };
            let p = e.path();
            if ft.is_symlink() {
                continue;
            }
            if ft.is_dir() {
                if depth < max {
                    walk(&p, depth + 1, max, cutoff, out);
                }
            } else if p.extension().is_some_and(|x| x == "jsonl") {
                if let Ok(m) = e.metadata().and_then(|m| m.modified()) {
                    if m >= cutoff {
                        out.push((p, m));
                    }
                }
            }
        }
    }
    let mut out = Vec::new();
    walk(root, 0, max_depth, cutoff, &mut out);
    out.sort_by(|a, b| b.1.cmp(&a.1));
    out.truncate(4_000);
    out.into_iter().map(|(p, _)| p).collect()
}

/// Đọc token OAuth Claude Code (Windows lưu ở `~/.claude/.credentials.json`) rồi gọi endpoint usage.
/// Endpoint không có tài liệu chính thức; KHÔNG tự làm mới token.
fn fetch_oauth_usage() -> Result<LimitSnapshot, String> {
    let path = paths::claude_config_dir().join(".credentials.json");
    let text = std::fs::read_to_string(&path).map_err(|_| "Chưa thấy đăng nhập Claude Code trên máy này.".to_string())?;
    let v: Value = serde_json::from_str(&text).map_err(|_| "File đăng nhập Claude Code không đọc được.".to_string())?;
    let oauth = v.get("claudeAiOauth").ok_or("Chưa thấy đăng nhập Claude Code (OAuth).")?;
    let token = oauth.get("accessToken").and_then(Value::as_str).filter(|t| !t.is_empty()).ok_or("Thiếu token.")?;
    if let Some(exp) = oauth.get("expiresAt").and_then(Value::as_f64) {
        if exp / 1000.0 < Utc::now().timestamp() as f64 {
            return Err("Token Claude Code đã hết hạn — mở Claude Code một lần để làm mới.".into());
        }
    }
    let resp = ureq::get("https://api.anthropic.com/api/oauth/usage")
        .header("Authorization", &format!("Bearer {token}"))
        .header("anthropic-beta", "oauth-2025-04-20")
        .header("Accept", "application/json")
        .header("User-Agent", concat!("MacHub-Windows/", env!("CARGO_PKG_VERSION")))
        .call();
    let mut resp = match resp {
        Ok(r) => r,
        Err(ureq::Error::StatusCode(401)) | Err(ureq::Error::StatusCode(403)) => {
            return Err("Token bị từ chối — đăng nhập lại Claude Code.".into())
        }
        Err(ureq::Error::StatusCode(429)) => return Err("Bị giới hạn tần suất, thử lại sau.".into()),
        Err(e) => return Err(format!("Lỗi mạng: {e}")),
    };
    let body = resp.body_mut().read_to_string().map_err(|e| e.to_string())?;
    claude::parse_oauth_usage(&body, Utc::now()).ok_or_else(|| "Định dạng phản hồi đã thay đổi.".into())
}

pub fn refresh_hook_binary() -> Result<(), String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let name = if cfg!(windows) { "machub-agent-hook.exe" } else { "machub-agent-hook" };
    let src = exe.with_file_name(name);
    if !src.exists() {
        return Err("Không tìm thấy machub-agent-hook trong thư mục cài MacHub.".into());
    }
    let dst = paths::hook_binary();
    std::fs::create_dir_all(dst.parent().unwrap()).map_err(|e| e.to_string())?;
    let tmp = dst.with_extension("tmp");
    std::fs::copy(&src, &tmp).map_err(|e| e.to_string())?;
    // Windows không cho thay file đang chạy: nếu hook đang chạy dở thì giữ bản cũ, lần sau cập nhật.
    if std::fs::rename(&tmp, &dst).is_err() {
        let _ = std::fs::remove_file(&tmp);
    }
    Ok(())
}

fn install_hooks(status_line: bool, s: &AgentSettings) -> Result<Option<PathBuf>, String> {
    refresh_hook_binary()?;
    let path = paths::claude_settings();
    let settings = installer::load(&path).map_err(|e| e.to_string())?;
    let opts = Options { observe: true, approvals: s.approvals_enabled, status_line };
    let (updated, previous) = Installer::new(&paths::hook_binary()).install(&settings, opts);
    let cfg_path = paths::hook_config();
    let mut cfg = HookConfig::load(&cfg_path);
    if previous.is_some() {
        cfg.previous_status_line = previous;
    }
    cfg.approval_timeout_seconds = s.approval_timeout;
    cfg.save(&cfg_path).map_err(|e| e.to_string())?;
    installer::save(&updated, &path, Utc::now().timestamp()).map_err(|e| e.to_string())
}

fn uninstall_hooks() -> Result<Option<PathBuf>, String> {
    let path = paths::claude_settings();
    let settings = installer::load(&path).map_err(|e| e.to_string())?;
    let cfg_path = paths::hook_config();
    let mut cfg = HookConfig::load(&cfg_path);
    let updated = installer::uninstall(&settings, cfg.previous_status_line.as_ref());
    let b = installer::save(&updated, &path, Utc::now().timestamp()).map_err(|e| e.to_string())?;
    cfg.previous_status_line = None;
    let _ = cfg.save(&cfg_path);
    Ok(b)
}

// ───────────── Bảo mật named pipe ─────────────

#[cfg(windows)]
struct PipeSecurity {
    attrs: windows::Win32::Security::SECURITY_ATTRIBUTES,
}

/// DACL chỉ cho chủ sở hữu (tài khoản hiện tại) và SYSTEM: "D:P(A;;GA;;;OW)(A;;GA;;;SY)".
/// Mặc định pipe cho phép Everyone đọc; ta siết lại để tiến trình của user khác không kết nối được.
/// Bộ mô tả được tạo MỘT lần và dùng lại cho mọi instance pipe.
#[cfg(windows)]
fn owner_only_security_attributes() -> Option<PipeSecurity> {
    use std::sync::OnceLock;
    use windows::core::w;
    use windows::Win32::Security::Authorization::{ConvertStringSecurityDescriptorToSecurityDescriptorW, SDDL_REVISION_1};
    use windows::Win32::Security::{PSECURITY_DESCRIPTOR, SECURITY_ATTRIBUTES};
    static SD: OnceLock<usize> = OnceLock::new();
    let ptr = *SD.get_or_init(|| {
        let mut sd = PSECURITY_DESCRIPTOR::default();
        let ok = unsafe {
            ConvertStringSecurityDescriptorToSecurityDescriptorW(w!("D:P(A;;GA;;;OW)(A;;GA;;;SY)"), SDDL_REVISION_1, &mut sd, None)
        };
        if ok.is_ok() { sd.0 as usize } else { 0 }
    });
    if ptr == 0 {
        return None;
    }
    Some(PipeSecurity {
        attrs: SECURITY_ATTRIBUTES {
            nLength: std::mem::size_of::<SECURITY_ATTRIBUTES>() as u32,
            lpSecurityDescriptor: ptr as *mut std::ffi::c_void,
            bInheritHandle: false.into(),
        },
    })
}
