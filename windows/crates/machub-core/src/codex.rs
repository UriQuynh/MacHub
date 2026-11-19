// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

//! Rollout JSONL của Codex CLI (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`).

use crate::{get_f64, get_str, get_u64, labels, parse_time, LimitSnapshot, LimitSource, LimitWindow, Provider, UsageRecord};
use chrono::{DateTime, Duration, TimeZone, Utc};
use serde::Serialize;
use serde_json::Value;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub enum CodexState {
    Running,
    Finished,
    #[default]
    Idle,
}

/// Đọc dần một file rollout; giữ trạng thái phiên, token và hạn mức mới nhất.
#[derive(Debug, Clone, Default)]
pub struct RolloutAccumulator {
    pub session_id: Option<String>,
    pub cwd: Option<String>,
    pub branch: Option<String>,
    pub model: Option<String>,
    pub started_at: Option<DateTime<Utc>>,
    pub last_activity: Option<DateTime<Utc>>,
    pub state: CodexState,
    pub last_user_message: Option<String>,
    pub last_agent_message: Option<String>,
    pub total_tokens: u64,
    pub limits: Option<LimitSnapshot>,
    pending: Vec<UsageRecord>,
    last_total: Option<u64>,
}

impl RolloutAccumulator {
    pub fn consume_line(&mut self, line: &str) {
        if let Ok(v) = serde_json::from_str::<Value>(line) {
            self.consume(&v);
        }
    }

    pub fn consume(&mut self, v: &Value) {
        let ts = parse_time(get_str(v, &["timestamp"]));
        if let Some(t) = ts {
            self.last_activity = Some(self.last_activity.map_or(t, |l| l.max(t)));
        }
        let Some(p) = v.get("payload") else { return };
        match get_str(v, &["type"]) {
            Some("session_meta") => {
                if let Some(id) = get_str(p, &["id"]) {
                    self.session_id = Some(id.into());
                }
                if let Some(c) = get_str(p, &["cwd"]) {
                    self.cwd = Some(c.into());
                }
                if let Some(b) = get_str(p, &["git", "branch"]) {
                    self.branch = Some(b.into());
                }
                if let Some(m) = get_str(p, &["model"]) {
                    self.model = Some(m.into());
                }
                self.started_at = parse_time(get_str(p, &["timestamp"])).or(ts).or(self.started_at);
            }
            Some("turn_context") => {
                if let Some(m) = get_str(p, &["model"]) {
                    self.model = Some(m.into());
                }
                if let Some(c) = get_str(p, &["cwd"]) {
                    self.cwd = Some(c.into());
                }
            }
            Some("event_msg") => self.consume_event(p, ts),
            _ => {}
        }
    }

    fn consume_event(&mut self, p: &Value, ts: Option<DateTime<Utc>>) {
        match get_str(p, &["type"]) {
            Some("task_started") => self.state = CodexState::Running,
            Some("task_complete") => {
                self.state = CodexState::Finished;
                if let Some(m) = get_str(p, &["last_agent_message"]) {
                    self.last_agent_message = Some(m.into());
                }
            }
            Some("turn_aborted") => self.state = CodexState::Finished,
            Some("user_message") => {
                if let Some(m) = get_str(p, &["message"]) {
                    self.last_user_message = Some(m.into());
                }
                self.state = CodexState::Running;
            }
            Some("agent_message") => {
                if let Some(m) = get_str(p, &["message"]) {
                    self.last_agent_message = Some(m.into());
                }
            }
            Some("token_count") => {
                if let (Some(info), Some(ts)) = (p.get("info").filter(|i| !i.is_null()), ts) {
                    let total = get_u64(info, &["total_token_usage", "total_tokens"]);
                    // Codex đôi khi phát lại cùng token_count: chỉ tính khi tổng tăng.
                    if self.last_total.is_none_or(|l| total > l) {
                        if let Some(last) = info.get("last_token_usage") {
                            let input = get_u64(last, &["input_tokens"]);
                            let cached = get_u64(last, &["cached_input_tokens"]);
                            let output = get_u64(last, &["output_tokens"]);
                            let mut r = UsageRecord::new(
                                Provider::Codex,
                                ts,
                                self.model.as_deref().unwrap_or("codex"),
                                input.saturating_sub(cached),
                                output,
                            );
                            r.cache_read_tokens = cached;
                            r.project = self.cwd.clone();
                            r.session_id = self.session_id.clone();
                            self.pending.push(r);
                            self.last_total = Some(total);
                            self.total_tokens = total;
                        }
                    }
                }
                if let (Some(rl), Some(ts)) = (p.get("rate_limits").filter(|r| !r.is_null()), ts) {
                    let windows: Vec<LimitWindow> = [("primary", "5H"), ("secondary", "7D")]
                        .iter()
                        .filter_map(|(key, fallback)| {
                            let w = rl.get(*key)?;
                            let pct = get_f64(w, &["used_percent"])?;
                            let minutes = get_f64(w, &["window_minutes"]).map(|m| m as u64);
                            let resets = get_f64(w, &["resets_at"])
                                .and_then(|s| Utc.timestamp_opt(s as i64, 0).single())
                                .or_else(|| get_f64(w, &["resets_in_seconds"]).map(|s| ts + Duration::seconds(s as i64)));
                            Some(LimitWindow {
                                id: key.to_string(),
                                label: labels::codex(minutes, fallback),
                                used_percent: pct,
                                resets_at: resets,
                                window_minutes: minutes,
                            })
                        })
                        .collect();
                    if !windows.is_empty() {
                        self.limits = Some(LimitSnapshot {
                            provider: Provider::Codex,
                            windows,
                            observed_at: ts,
                            source: LimitSource::CodexLog,
                            plan: get_str(rl, &["plan_type"]).map(str::to_string),
                        });
                    }
                }
            }
            _ => {}
        }
    }

    /// Lấy các bản ghi token mới kể từ lần gọi trước.
    pub fn drain_records(&mut self) -> Vec<UsageRecord> {
        std::mem::take(&mut self.pending)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const ROLLOUT: &[&str] = &[
        r#"{"timestamp":"2026-11-18T09:00:00.000Z","type":"session_meta","payload":{"id":"cx-1","timestamp":"2026-11-18T09:00:00.000Z","cwd":"C:\\code\\MacHub","git":{"branch":"agent-monitor"}}}"#,
        r#"{"timestamp":"2026-11-18T09:00:01.000Z","type":"turn_context","payload":{"model":"gpt-5.3-codex"}}"#,
        r#"{"timestamp":"2026-11-18T09:00:02.000Z","type":"event_msg","payload":{"type":"task_started"}}"#,
        r#"{"timestamp":"2026-11-18T09:00:02.500Z","type":"event_msg","payload":{"type":"user_message","message":"viết test"}}"#,
        r#"{"timestamp":"2026-11-18T09:00:10.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":1200},"last_token_usage":{"input_tokens":1000,"cached_input_tokens":600,"output_tokens":200}},"rate_limits":{"primary":{"used_percent":4.0,"window_minutes":300,"resets_at":1795000000},"secondary":{"used_percent":13.0,"window_minutes":10080,"resets_in_seconds":3600},"plan_type":"pro"}}}"#,
        r#"{"timestamp":"2026-11-18T09:00:10.100Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":1200},"last_token_usage":{"input_tokens":1000,"cached_input_tokens":600,"output_tokens":200}},"rate_limits":null}}"#,
        r#"{"timestamp":"2026-11-18T09:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":1500},"last_token_usage":{"input_tokens":250,"cached_input_tokens":0,"output_tokens":50}}}}"#,
        r#"{"timestamp":"2026-11-18T09:01:05.000Z","type":"event_msg","payload":{"type":"task_complete","last_agent_message":"Xong 12 test"}}"#,
    ];

    #[test]
    fn accumulates() {
        let mut a = RolloutAccumulator::default();
        ROLLOUT.iter().for_each(|l| a.consume_line(l));
        assert_eq!(a.session_id.as_deref(), Some("cx-1"));
        assert_eq!(a.branch.as_deref(), Some("agent-monitor"));
        assert_eq!(a.model.as_deref(), Some("gpt-5.3-codex"));
        assert_eq!(a.state, CodexState::Finished);
        assert_eq!(a.total_tokens, 1500);
        let r = a.drain_records();
        assert_eq!(r.len(), 2, "token_count lặp lại không được tính");
        assert_eq!(r[0].input_tokens, 400);
        assert_eq!(r[0].cache_read_tokens, 600);
        assert!(a.drain_records().is_empty());
        let l = a.limits.unwrap();
        assert_eq!(l.plan.as_deref(), Some("pro"));
        assert_eq!(l.windows[0].label, "5H");
        assert_eq!(l.windows[1].label, "7D");
        let ts = parse_time(Some("2026-11-18T09:00:10.000Z")).unwrap();
        assert_eq!(l.windows[1].resets_at, Some(ts + Duration::seconds(3600)));
    }

    #[test]
    fn running_until_complete() {
        let mut a = RolloutAccumulator::default();
        ROLLOUT[..4].iter().for_each(|l| a.consume_line(l));
        assert_eq!(a.state, CodexState::Running);
    }
}
