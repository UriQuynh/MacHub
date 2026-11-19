// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

//! Thêm / gỡ hook MacHub trong `settings.json` của Claude Code — cùng quy tắc với bản macOS:
//! chỉ đụng mục chứa `machub-agent-hook`, giữ nguyên thứ tự & cấu hình khác, sao lưu trước khi ghi,
//! từ chối file JSON hỏng, bọc statusLine cũ và trả lại khi gỡ.

use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};
use std::path::{Path, PathBuf};

pub const MARKER: &str = "machub-agent-hook";

pub const OBSERVED_EVENTS: [&str; 7] =
    ["SessionStart", "SessionEnd", "UserPromptSubmit", "Stop", "SubagentStart", "SubagentStop", "Notification"];

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Options {
    pub observe: bool,
    pub approvals: bool,
    pub status_line: bool,
}

impl Default for Options {
    fn default() -> Self {
        Options { observe: true, approvals: true, status_line: true }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct State {
    pub observe: bool,
    pub approvals: bool,
    pub status_line: bool,
    pub installed: bool,
}

fn is_ours(handler: &Value) -> bool {
    handler.get("command").and_then(Value::as_str).is_some_and(|c| c.contains(MARKER))
}

pub fn state(settings: &Value) -> State {
    let mut s = State::default();
    if let Some(hooks) = settings.get("hooks").and_then(Value::as_object) {
        for (event, groups) in hooks {
            let ours = groups.as_array().is_some_and(|gs| {
                gs.iter().any(|g| g.get("hooks").and_then(Value::as_array).is_some_and(|hs| hs.iter().any(is_ours)))
            });
            if ours {
                if event == "PermissionRequest" {
                    s.approvals = true;
                } else {
                    s.observe = true;
                }
            }
        }
    }
    s.status_line = settings.get("statusLine").is_some_and(is_ours);
    s.installed = s.observe || s.approvals || s.status_line;
    s
}

/// Bỏ mọi hook của MacHub; xóa nhóm / sự kiện rỗng do việc bỏ này tạo ra.
pub fn remove_our_hooks(settings: &Value) -> Value {
    let mut out = settings.clone();
    let Some(obj) = out.as_object_mut() else { return out };
    let Some(hooks) = obj.get_mut("hooks").and_then(Value::as_object_mut) else { return out };
    let mut empty_events = Vec::new();
    for (event, groups) in hooks.iter_mut() {
        let Some(gs) = groups.as_array_mut() else { continue };
        let mut kept_groups = Vec::new();
        for g in gs.drain(..) {
            match g.get("hooks").and_then(Value::as_array) {
                Some(hs) => {
                    let kept: Vec<Value> = hs.iter().filter(|h| !is_ours(h)).cloned().collect();
                    if kept.len() == hs.len() {
                        kept_groups.push(g);
                    } else if !kept.is_empty() {
                        let mut g2 = g.clone();
                        g2["hooks"] = Value::Array(kept);
                        kept_groups.push(g2);
                    }
                }
                None => kept_groups.push(g),
            }
        }
        if kept_groups.is_empty() {
            empty_events.push(event.clone());
        }
        *gs = kept_groups;
    }
    for e in empty_events {
        hooks.shift_remove(&e);
    }
    if hooks.is_empty() {
        obj.shift_remove("hooks");
    }
    out
}

pub struct Installer {
    pub hook_command_path: String,
}

impl Installer {
    pub fn new(hook_path: &Path) -> Self {
        Installer { hook_command_path: crate::paths::command_path(hook_path) }
    }

    fn command(&self, mode: &str) -> String {
        format!("\"{}\" {mode}", self.hook_command_path)
    }

    /// (settings mới, statusLine cũ cần lưu lại nếu có).
    pub fn install(&self, settings: &Value, opts: Options) -> (Value, Option<Value>) {
        let mut out = remove_our_hooks(settings);
        if !out.is_object() {
            out = Value::Object(Map::new());
        }
        let obj = out.as_object_mut().expect("object");
        let mut add = |event: &str, handler: Value| {
            let hooks = obj.entry("hooks").or_insert_with(|| Value::Object(Map::new()));
            let groups = hooks.as_object_mut().expect("hooks object").entry(event).or_insert_with(|| json!([]));
            if let Some(a) = groups.as_array_mut() {
                a.push(json!({ "hooks": [handler] }));
            }
        };
        if opts.observe {
            for e in OBSERVED_EVENTS {
                add(e, json!({"type": "command", "command": self.command("claude"), "timeout": 10, "async": true}));
            }
        }
        if opts.approvals {
            add("PermissionRequest", json!({"type": "command", "command": self.command("claude"), "timeout": 600}));
        }

        let mut previous = None;
        if opts.status_line {
            let current = obj.get("statusLine").cloned();
            if let Some(c) = &current {
                if !is_ours(c) {
                    previous = Some(c.clone());
                }
            }
            let mut line = json!({"type": "command", "command": self.command("statusline")});
            if let Some(p) = current.as_ref().and_then(|c| c.get("padding")) {
                line["padding"] = p.clone();
            }
            obj.insert("statusLine".into(), line);
        }
        (out, previous)
    }
}

/// Gỡ: bỏ hook MacHub, trả lại statusLine cũ (hoặc xóa nếu trước đó không có).
pub fn uninstall(settings: &Value, previous_status_line: Option<&Value>) -> Value {
    let mut out = remove_our_hooks(settings);
    if let Some(obj) = out.as_object_mut() {
        if obj.get("statusLine").is_some_and(is_ours) {
            match previous_status_line {
                Some(p) => {
                    obj.insert("statusLine".into(), p.clone());
                }
                None => {
                    obj.shift_remove("statusLine");
                }
            }
        }
    }
    out
}

#[derive(Debug)]
pub enum Error {
    InvalidJson,
    NotAnObject,
    Io(std::io::Error),
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Error::InvalidJson => write!(f, "settings.json không phải JSON hợp lệ — MacHub không sửa để tránh làm hỏng cấu hình."),
            Error::NotAnObject => write!(f, "settings.json phải là một object JSON."),
            Error::Io(e) => write!(f, "{e}"),
        }
    }
}

pub fn load(path: &Path) -> Result<Value, Error> {
    let text = match std::fs::read_to_string(path) {
        Ok(t) if !t.trim().is_empty() => t,
        Ok(_) => return Ok(json!({})),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(json!({})),
        Err(e) => return Err(Error::Io(e)),
    };
    let v: Value = serde_json::from_str(text.trim_start_matches('\u{feff}')).map_err(|_| Error::InvalidJson)?;
    if !v.is_object() {
        return Err(Error::NotAnObject);
    }
    Ok(v)
}

/// Ghi (qua file tạm rồi đổi tên), sao lưu bản cũ. Trả về đường dẫn bản sao lưu.
pub fn save(settings: &Value, path: &Path, stamp: i64) -> Result<Option<PathBuf>, Error> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).map_err(Error::Io)?;
    }
    let mut backup = None;
    if path.exists() {
        let name = format!("{}.machub-backup-{stamp}", path.file_name().unwrap_or_default().to_string_lossy());
        let b = path.with_file_name(name);
        std::fs::copy(path, &b).map_err(Error::Io)?;
        backup = Some(b);
    }
    let text = serde_json::to_string_pretty(settings).map_err(|_| Error::InvalidJson)? + "\n";
    let tmp = path.with_extension("json.machub-tmp");
    std::fs::write(&tmp, text).map_err(Error::Io)?;
    std::fs::rename(&tmp, path).map_err(Error::Io)?;
    Ok(backup)
}

/// Cấu hình phía hook (`agent-hook.json`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HookConfig {
    #[serde(default)]
    pub previous_status_line: Option<Value>,
    #[serde(default = "default_timeout")]
    pub approval_timeout_seconds: f64,
}

fn default_timeout() -> f64 {
    120.0
}

impl Default for HookConfig {
    fn default() -> Self {
        HookConfig { previous_status_line: None, approval_timeout_seconds: default_timeout() }
    }
}

impl HookConfig {
    pub fn previous_command(&self) -> Option<String> {
        self.previous_status_line.as_ref()?.get("command")?.as_str().map(str::to_string)
    }

    pub fn load(path: &Path) -> HookConfig {
        std::fs::read_to_string(path).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default()
    }

    pub fn save(&self, path: &Path) -> std::io::Result<()> {
        if let Some(d) = path.parent() {
            std::fs::create_dir_all(d)?;
        }
        std::fs::write(path, serde_json::to_string_pretty(self)?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn user_settings() -> Value {
        json!({
            "model": "sonnet",
            "permissions": {"allow": ["Bash(npm test)"]},
            "statusLine": {"type": "command", "command": "~/.claude/statusline.sh", "padding": 0},
            "hooks": {
                "Stop": [{"hooks": [{"type": "command", "command": "say done"}]}],
                "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "./guard.sh"}]}]
            }
        })
    }

    fn inst() -> Installer {
        Installer::new(Path::new(r"C:\Users\Uri\AppData\Roaming\MacHub\bin\machub-agent-hook.exe"))
    }

    #[test]
    fn install_keeps_user_config() {
        let (out, prev) = inst().install(&user_settings(), Options::default());
        assert_eq!(out["model"], "sonnet");
        assert_eq!(out["hooks"]["Stop"].as_array().unwrap().len(), 2);
        assert_eq!(out["hooks"]["Stop"][0]["hooks"][0]["command"], "say done");
        assert_eq!(
            out["hooks"]["Stop"][1]["hooks"][0]["command"],
            "\"C:/Users/Uri/AppData/Roaming/MacHub/bin/machub-agent-hook.exe\" claude"
        );
        assert_eq!(out["hooks"]["Stop"][1]["hooks"][0]["async"], true);
        assert!(out["hooks"]["PermissionRequest"][0]["hooks"][0].get("async").is_none());
        assert_eq!(out["statusLine"]["padding"], 0);
        assert_eq!(prev.unwrap()["command"], "~/.claude/statusline.sh");
        let s = state(&out);
        assert!(s.observe && s.approvals && s.status_line && s.installed);
        // Thứ tự khóa của người dùng được giữ (preserve_order).
        let keys: Vec<_> = out.as_object().unwrap().keys().cloned().collect();
        assert_eq!(&keys[..3], ["model", "permissions", "statusLine"]);
    }

    #[test]
    fn idempotent_and_reversible() {
        let i = inst();
        let (once, prev) = i.install(&user_settings(), Options::default());
        let (twice, prev2) = i.install(&once, Options::default());
        assert_eq!(once, twice);
        assert!(prev2.is_none());
        assert_eq!(uninstall(&twice, prev.as_ref()), user_settings());
        assert!(!state(&user_settings()).installed);
        let (from_empty, p) = i.install(&json!({}), Options::default());
        assert_eq!(uninstall(&from_empty, p.as_ref()), json!({}));
    }

    #[test]
    fn file_io() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("settings.json");
        std::fs::write(&p, "{ not json").unwrap();
        assert!(matches!(load(&p), Err(Error::InvalidJson)));
        std::fs::write(&p, "\u{feff}{\"model\":\"opus\"}").unwrap();
        let v = load(&p).unwrap();
        let backup = save(&json!({"model":"opus","x":1}), &p, 7).unwrap().unwrap();
        assert!(std::fs::read_to_string(backup).unwrap().contains("opus"));
        assert_eq!(load(&p).unwrap()["x"], 1);
        assert_eq!(v["model"], "opus");
        assert_eq!(load(&dir.path().join("missing.json")).unwrap(), json!({}));
    }
}
