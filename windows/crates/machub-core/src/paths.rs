// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

use std::env;
use std::path::PathBuf;

fn env_path(key: &str) -> Option<PathBuf> {
    env::var_os(key).filter(|v| !v.is_empty()).map(PathBuf::from)
}

pub fn home() -> PathBuf {
    env_path("USERPROFILE").or_else(|| env_path("HOME")).unwrap_or_else(|| PathBuf::from("."))
}

/// `%APPDATA%\MacHub` (hoặc `MACHUB_AGENT_SUPPORT_DIR` khi kiểm thử).
pub fn support_dir() -> PathBuf {
    if let Some(p) = env_path("MACHUB_AGENT_SUPPORT_DIR") {
        return p;
    }
    env_path("APPDATA").map(|a| a.join("MacHub")).unwrap_or_else(|| home().join(".machub"))
}

pub fn hook_binary() -> PathBuf {
    let name = if cfg!(windows) { "machub-agent-hook.exe" } else { "machub-agent-hook" };
    support_dir().join("bin").join(name)
}

pub fn hook_config() -> PathBuf {
    support_dir().join("agent-hook.json")
}

/// Tên kênh hook → app.
/// Windows: named pipe `\\.\pipe\machub-agent-<user>`; nơi khác (kiểm thử): socket Unix trong thư mục hỗ trợ.
pub fn pipe_name() -> String {
    if let Ok(p) = env::var("MACHUB_AGENT_PIPE") {
        if !p.is_empty() {
            return p;
        }
    }
    if cfg!(windows) {
        let user: String = env::var("USERNAME")
            .unwrap_or_else(|_| "user".into())
            .chars()
            .map(|c| if c.is_ascii_alphanumeric() { c.to_ascii_lowercase() } else { '_' })
            .collect();
        format!(r"\\.\pipe\machub-agent-{user}")
    } else {
        support_dir().join("agent.sock").to_string_lossy().into_owned()
    }
}

pub fn claude_config_dir() -> PathBuf {
    env_path("CLAUDE_CONFIG_DIR").unwrap_or_else(|| home().join(".claude"))
}

pub fn claude_settings() -> PathBuf {
    claude_config_dir().join("settings.json")
}

pub fn claude_project_dirs() -> Vec<PathBuf> {
    vec![claude_config_dir().join("projects"), home().join(".config").join("claude").join("projects")]
}

pub fn codex_sessions_dir() -> PathBuf {
    env_path("CODEX_HOME").unwrap_or_else(|| home().join(".codex")).join("sessions")
}

/// Đường dẫn dùng trong lệnh hook: dấu `/` để chạy được cả trong Git Bash (Claude Code dùng) lẫn cmd.
pub fn command_path(p: &std::path::Path) -> String {
    p.to_string_lossy().replace('\\', "/")
}
