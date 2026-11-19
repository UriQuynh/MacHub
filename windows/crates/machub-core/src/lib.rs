// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.
//
// Lõi theo dõi agent dùng chung cho app Tauri và `machub-agent-hook.exe`.
// Cùng định dạng và quy tắc với AgentKit của bản macOS (Sources/AgentKit).

pub mod claude;
pub mod codex;
pub mod format;
pub mod installer;
pub mod lines;
pub mod model;
pub mod paths;
pub mod pricing;
pub mod summary;
pub mod wire;

pub use model::*;

/// Đi theo đường dẫn khóa trong JSON: `get(&v, &["message", "usage"])`.
pub fn get<'a>(v: &'a serde_json::Value, keys: &[&str]) -> Option<&'a serde_json::Value> {
    let mut cur = v;
    for k in keys {
        cur = cur.get(*k)?;
    }
    Some(cur)
}

pub fn get_str<'a>(v: &'a serde_json::Value, keys: &[&str]) -> Option<&'a str> {
    get(v, keys)?.as_str()
}

pub fn get_f64(v: &serde_json::Value, keys: &[&str]) -> Option<f64> {
    let x = get(v, keys)?;
    x.as_f64().or_else(|| x.as_str()?.parse().ok())
}

pub fn get_u64(v: &serde_json::Value, keys: &[&str]) -> u64 {
    get_f64(v, keys).map(|f| if f < 0.0 { 0 } else { f as u64 }).unwrap_or(0)
}

/// ISO 8601 (có/không phần lẻ giây, có múi giờ) → thời điểm UTC.
pub fn parse_time(s: Option<&str>) -> Option<chrono::DateTime<chrono::Utc>> {
    let s = s?;
    chrono::DateTime::parse_from_rfc3339(s).ok().map(|d| d.with_timezone(&chrono::Utc))
}
