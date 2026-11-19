// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

//! Transcript JSONL, statusLine và phản hồi OAuth usage của Claude Code.

use crate::{get, get_f64, get_str, get_u64, labels, parse_time, LimitSnapshot, LimitSource, LimitWindow, Provider, UsageRecord};
use chrono::{DateTime, TimeZone, Utc};
use serde_json::Value;

/// Khóa khử trùng lặp (Claude Code có thể ghi lại cùng phản hồi khi stream/resume/fork).
pub fn dedupe_key(line: &Value) -> Option<String> {
    let id = get_str(line, &["message", "id"])?;
    Some(format!("{id}:{}", get_str(line, &["requestId"]).unwrap_or("")))
}

/// Dòng assistant có `message.usage` → bản ghi token.
pub fn usage_record(line: &Value) -> Option<UsageRecord> {
    if get_str(line, &["type"]) != Some("assistant") {
        return None;
    }
    let usage = get(line, &["message", "usage"])?.as_object()?;
    let usage = Value::Object(usage.clone());
    let model = get_str(line, &["message", "model"]).unwrap_or("unknown");
    if model == "<synthetic>" {
        return None;
    }
    let ts = parse_time(get_str(line, &["timestamp"]))?;

    let input = get_u64(&usage, &["input_tokens"]);
    let output = get_u64(&usage, &["output_tokens"]);
    let read = get_u64(&usage, &["cache_read_input_tokens"]);
    let mut c5 = get_u64(&usage, &["cache_creation_input_tokens"]);
    let mut c1 = 0;
    if get(&usage, &["cache_creation", "ephemeral_5m_input_tokens"]).is_some()
        || get(&usage, &["cache_creation", "ephemeral_1h_input_tokens"]).is_some()
    {
        c5 = get_u64(&usage, &["cache_creation", "ephemeral_5m_input_tokens"]);
        c1 = get_u64(&usage, &["cache_creation", "ephemeral_1h_input_tokens"]);
    }
    if input + output + read + c5 + c1 == 0 {
        return None;
    }
    let mut r = UsageRecord::new(Provider::Claude, ts, model, input, output);
    r.project = get_str(line, &["cwd"]).map(str::to_string);
    r.session_id = get_str(line, &["sessionId"]).map(str::to_string);
    r.cache_write_5m_tokens = c5;
    r.cache_write_1h_tokens = c1;
    r.cache_read_tokens = read;
    Some(r)
}

/// Model của phản hồi assistant gần nhất trong đoạn cuối transcript.
pub fn last_model(tail: &str) -> Option<String> {
    tail.lines().rev().find_map(|raw| {
        let v: Value = serde_json::from_str(raw).ok()?;
        if get_str(&v, &["type"]) != Some("assistant") {
            return None;
        }
        let m = get_str(&v, &["message", "model"])?;
        (m != "<synthetic>").then(|| m.to_string())
    })
}

fn time_value(v: Option<&Value>) -> Option<DateTime<Utc>> {
    let v = v?;
    if let Some(s) = v.as_str() {
        return parse_time(Some(s));
    }
    let secs = v.as_f64()?;
    Utc.timestamp_opt(secs as i64, 0).single()
}

/// 5H, 7D trước; cửa sổ theo model sau, theo tên.
pub fn sort_windows(windows: &mut [LimitWindow]) {
    fn rank(id: &str) -> u8 {
        match id {
            "five_hour" => 0,
            "seven_day" => 1,
            _ => 2,
        }
    }
    windows.sort_by(|a, b| rank(&a.id).cmp(&rank(&b.id)).then_with(|| a.id.cmp(&b.id)));
}

/// `GET https://api.anthropic.com/api/oauth/usage` (không có tài liệu chính thức → đọc mềm dẻo).
pub fn parse_oauth_usage(body: &str, observed_at: DateTime<Utc>) -> Option<LimitSnapshot> {
    let v: Value = serde_json::from_str(body).ok()?;
    let mut windows: Vec<LimitWindow> = v
        .as_object()?
        .iter()
        .filter_map(|(k, w)| {
            let pct = get_f64(w, &["utilization"])?;
            Some(LimitWindow {
                id: k.clone(),
                label: labels::claude(k),
                used_percent: pct,
                resets_at: time_value(w.get("resets_at")),
                window_minutes: None,
            })
        })
        .collect();
    if windows.is_empty() {
        return None;
    }
    sort_windows(&mut windows);
    Some(LimitSnapshot { provider: Provider::Claude, windows, observed_at, source: LimitSource::OAuth, plan: None })
}

/// JSON Claude Code đưa vào lệnh statusLine qua stdin.
#[derive(Debug, Clone, PartialEq)]
pub struct StatusLine {
    pub session_id: Option<String>,
    pub model_id: Option<String>,
    pub model_name: Option<String>,
    pub cwd: Option<String>,
    pub context_used_percent: Option<f64>,
    pub limits: Option<LimitSnapshot>,
}

impl StatusLine {
    pub fn parse(p: &Value, observed_at: DateTime<Utc>) -> StatusLine {
        let mut windows: Vec<LimitWindow> = p
            .get("rate_limits")
            .and_then(Value::as_object)
            .map(|rl| {
                rl.iter()
                    .filter_map(|(k, w)| {
                        let pct = get_f64(w, &["used_percentage"]).or_else(|| get_f64(w, &["utilization"]))?;
                        Some(LimitWindow {
                            id: k.clone(),
                            label: labels::claude(k),
                            used_percent: pct,
                            resets_at: time_value(w.get("resets_at")),
                            window_minutes: None,
                        })
                    })
                    .collect()
            })
            .unwrap_or_default();
        sort_windows(&mut windows);
        StatusLine {
            session_id: get_str(p, &["session_id"]).map(str::to_string),
            model_id: get_str(p, &["model", "id"]).map(str::to_string),
            model_name: get_str(p, &["model", "display_name"]).map(str::to_string),
            cwd: get_str(p, &["workspace", "current_dir"]).or_else(|| get_str(p, &["cwd"])).map(str::to_string),
            context_used_percent: get_f64(p, &["context_window", "used_percentage"]),
            limits: (!windows.is_empty()).then_some(LimitSnapshot {
                provider: Provider::Claude,
                windows,
                observed_at,
                source: LimitSource::StatusLine,
                plan: None,
            }),
        }
    }

    /// Dòng mặc định khi người dùng chưa có statusLine riêng.
    pub fn default_line(&self) -> String {
        let mut parts: Vec<String> = Vec::new();
        if let Some(m) = &self.model_name {
            parts.push(m.clone());
        }
        if let Some(l) = &self.limits {
            for w in l.windows.iter().filter(|w| w.id == "five_hour" || w.id == "seven_day") {
                parts.push(format!("{} {}%", w.label, w.used_percent.round() as i64));
            }
        }
        if let Some(c) = self.context_used_percent {
            parts.push(format!("ctx {}%", c.round() as i64));
        }
        parts.join(" · ")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn usage_line() {
        let line = json!({"type":"assistant","timestamp":"2026-11-18T10:00:00.123Z","sessionId":"s1","cwd":"C:\\code\\FTL_NTL",
            "requestId":"req_1","message":{"id":"msg_1","model":"claude-sonnet-5-5","usage":{"input_tokens":12,"output_tokens":340,
            "cache_creation_input_tokens":1000,"cache_read_input_tokens":20000,
            "cache_creation":{"ephemeral_5m_input_tokens":600,"ephemeral_1h_input_tokens":400}}}});
        let r = usage_record(&line).unwrap();
        assert_eq!(r.input_tokens, 12);
        assert_eq!(r.output_tokens, 340);
        assert_eq!(r.cache_read_tokens, 20000);
        assert_eq!(r.cache_write_5m_tokens, 600);
        assert_eq!(r.cache_write_1h_tokens, 400);
        assert_eq!(dedupe_key(&line).unwrap(), "msg_1:req_1");
    }

    #[test]
    fn ignores_other_lines() {
        assert!(usage_record(&json!({"type":"user"})).is_none());
        assert!(usage_record(&json!({"type":"assistant","timestamp":"2026-11-18T10:00:00Z",
            "message":{"model":"<synthetic>","usage":{"input_tokens":1}}})).is_none());
    }

    #[test]
    fn last_model_from_tail() {
        let tail = "{\"type\":\"assistant\",\"message\":{\"model\":\"a\"}}\n{\"type\":\"assistant\",\"message\":{\"model\":\"claude-opus-5-5\"}}\n{\"type\":\"assistant\",\"message\":{\"model\":\"<synthetic>\"}}";
        assert_eq!(last_model(tail).as_deref(), Some("claude-opus-5-5"));
    }

    #[test]
    fn oauth_usage() {
        let body = r#"{"five_hour":{"utilization":7.0,"resets_at":"2026-11-19T05:00:00+00:00"},
            "seven_day":{"utilization":28,"resets_at":"2026-11-23T14:00:00.000Z"},
            "seven_day_fable":{"utilization":0,"resets_at":null},"seven_day_opus":null,"extra_usage":{"is_enabled":false}}"#;
        let s = parse_oauth_usage(body, Utc::now()).unwrap();
        let ids: Vec<_> = s.windows.iter().map(|w| w.label.as_str()).collect();
        assert_eq!(ids, ["5H", "7D", "7D Fable"]);
        assert!(s.windows[2].resets_at.is_none());
        assert_eq!(s.headline().unwrap().id, "seven_day");
    }

    #[test]
    fn statusline() {
        let p = json!({"session_id":"abc","model":{"id":"claude-sonnet-5-5","display_name":"Sonnet 5.5"},
            "context_window":{"used_percentage":41.6},
            "rate_limits":{"seven_day":{"used_percentage":41.2,"resets_at":1795400000},
                           "five_hour":{"used_percentage":23.5,"resets_at":1795000000}}});
        let sl = StatusLine::parse(&p, Utc::now());
        assert_eq!(sl.default_line(), "Sonnet 5.5 · 5H 24% · 7D 41% · ctx 42%");
        assert_eq!(sl.limits.unwrap().windows[0].resets_at.unwrap().timestamp(), 1_795_000_000);
    }
}
