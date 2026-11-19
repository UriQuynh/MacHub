// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

//! Giao thức hook ↔ app: mỗi thông điệp là MỘT dòng JSON. Cùng tên trường với bản macOS.

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EnvelopeKind {
    #[serde(rename = "claude-hook")]
    ClaudeHook,
    #[serde(rename = "claude-statusline")]
    ClaudeStatusLine,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Envelope {
    pub version: u32,
    pub kind: EnvelopeKind,
    pub payload: Value,
    pub wants_reply: bool,
    /// mili-giây từ 1970.
    pub sent_at: i64,
    #[serde(rename = "parentPID")]
    pub parent_pid: u32,
}

impl Envelope {
    pub fn new(kind: EnvelopeKind, payload: Value, wants_reply: bool, parent_pid: u32) -> Self {
        Envelope { version: 1, kind, payload, wants_reply, sent_at: chrono::Utc::now().timestamp_millis(), parent_pid }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Reply {
    pub output: Option<Value>,
}

/// Quyết định cho yêu cầu quyền (PermissionRequest) của Claude Code.
#[derive(Debug, Clone, PartialEq)]
pub enum PermissionDecision {
    Allow,
    /// Cho phép và lưu quy tắc Claude Code gợi ý (`permission_suggestions`).
    AllowAlways(Value),
    Deny(String),
    /// Không quyết định: Claude Code tự hỏi trong terminal.
    AskInTerminal,
}

impl PermissionDecision {
    /// JSON hook in ra stdout. `None` = không in gì.
    pub fn hook_output(&self) -> Option<Value> {
        let decision = match self {
            PermissionDecision::Allow => json!({"behavior": "allow"}),
            PermissionDecision::AllowAlways(s) => {
                let rules: Vec<Value> = s
                    .as_array()
                    .map(|a| a.iter().filter(|r| r.get("behavior").and_then(Value::as_str) != Some("deny")).cloned().collect())
                    .unwrap_or_default();
                if rules.is_empty() {
                    json!({"behavior": "allow"})
                } else {
                    json!({"behavior": "allow", "updatedPermissions": rules})
                }
            }
            PermissionDecision::Deny(m) => json!({"behavior": "deny", "message": m}),
            PermissionDecision::AskInTerminal => return None,
        };
        Some(json!({"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": decision}}))
    }
}

/// Hook chỉ in ra nếu trả lời đúng là quyết định cho PermissionRequest.
pub fn is_permission_output(v: &Value) -> bool {
    crate::get_str(v, &["hookSpecificOutput", "hookEventName"]) == Some("PermissionRequest")
        && matches!(crate::get_str(v, &["hookSpecificOutput", "decision", "behavior"]), Some("allow") | Some("deny"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decisions() {
        assert_eq!(
            PermissionDecision::Allow.hook_output().unwrap(),
            json!({"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}})
        );
        let d = PermissionDecision::Deny("không".into()).hook_output().unwrap();
        assert_eq!(d["hookSpecificOutput"]["decision"]["message"], "không");
        assert!(PermissionDecision::AskInTerminal.hook_output().is_none());
        let s = json!([{"behavior":"allow","type":"addRules"},{"behavior":"deny","type":"addRules"}]);
        let a = PermissionDecision::AllowAlways(s).hook_output().unwrap();
        assert_eq!(a["hookSpecificOutput"]["decision"]["updatedPermissions"].as_array().unwrap().len(), 1);
        assert!(is_permission_output(&a));
        assert!(!is_permission_output(&json!({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}})));
    }

    #[test]
    fn envelope_round_trip() {
        let e = Envelope::new(EnvelopeKind::ClaudeHook, json!({"a":1}), true, 42);
        let s = serde_json::to_string(&e).unwrap();
        assert!(s.contains("\"kind\":\"claude-hook\"") && s.contains("\"wantsReply\":true") && s.contains("\"parentPID\":42"));
        assert_eq!(serde_json::from_str::<Envelope>(&s).unwrap(), e);
    }
}
