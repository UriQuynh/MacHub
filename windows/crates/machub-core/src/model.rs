// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, PartialOrd, Ord)]
#[serde(rename_all = "lowercase")]
pub enum Provider {
    Claude,
    Codex,
}

impl Provider {
    pub const ALL: [Provider; 2] = [Provider::Claude, Provider::Codex];

    pub fn display_name(self) -> &'static str {
        match self {
            Provider::Claude => "Claude",
            Provider::Codex => "Codex",
        }
    }
}

/// Token của MỘT phản hồi model (đã khử trùng lặp).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct UsageRecord {
    pub provider: Provider,
    pub timestamp: DateTime<Utc>,
    pub model: String,
    pub project: Option<String>,
    pub session_id: Option<String>,
    /// Đầu vào KHÔNG gồm phần đọc từ cache.
    pub input_tokens: u64,
    pub output_tokens: u64,
    pub cache_write_5m_tokens: u64,
    pub cache_write_1h_tokens: u64,
    pub cache_read_tokens: u64,
}

impl UsageRecord {
    pub fn new(provider: Provider, timestamp: DateTime<Utc>, model: &str, input: u64, output: u64) -> Self {
        UsageRecord {
            provider,
            timestamp,
            model: model.to_string(),
            project: None,
            session_id: None,
            input_tokens: input,
            output_tokens: output,
            cache_write_5m_tokens: 0,
            cache_write_1h_tokens: 0,
            cache_read_tokens: 0,
        }
    }

    pub fn cache_write_tokens(&self) -> u64 {
        self.cache_write_5m_tokens + self.cache_write_1h_tokens
    }

    pub fn total_tokens(&self) -> u64 {
        self.input_tokens + self.output_tokens + self.cache_write_tokens() + self.cache_read_tokens
    }
}

/// Một cửa sổ hạn mức (5 giờ, 7 ngày, 7 ngày theo model…).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LimitWindow {
    pub id: String,
    pub label: String,
    /// 0–100.
    pub used_percent: f64,
    pub resets_at: Option<DateTime<Utc>>,
    pub window_minutes: Option<u64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum LimitSource {
    #[serde(rename = "statusLine")]
    StatusLine,
    #[serde(rename = "OAuth")]
    OAuth,
    #[serde(rename = "log Codex")]
    CodexLog,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LimitSnapshot {
    pub provider: Provider,
    pub windows: Vec<LimitWindow>,
    pub observed_at: DateTime<Utc>,
    pub source: LimitSource,
    pub plan: Option<String>,
}

impl LimitSnapshot {
    /// Cửa sổ có % cao nhất (cho chip tóm tắt).
    pub fn headline(&self) -> Option<&LimitWindow> {
        self.windows
            .iter()
            .max_by(|a, b| a.used_percent.partial_cmp(&b.used_percent).unwrap_or(std::cmp::Ordering::Equal))
    }
}

pub mod labels {
    fn title_words(rest: &str) -> String {
        rest.split('_')
            .filter(|w| !w.is_empty())
            .map(|w| {
                let mut c = w.chars();
                match c.next() {
                    Some(f) => f.to_uppercase().collect::<String>() + &c.as_str().to_lowercase(),
                    None => String::new(),
                }
            })
            .collect::<Vec<_>>()
            .join(" ")
            .replace("Oauth", "OAuth")
    }

    /// "five_hour" → "5H", "seven_day" → "7D", "seven_day_opus" → "7D Opus".
    pub fn claude(key: &str) -> String {
        match key {
            "five_hour" => "5H".into(),
            "seven_day" => "7D".into(),
            _ => {
                if let Some(rest) = key.strip_prefix("seven_day_") {
                    format!("7D {}", title_words(rest))
                } else if let Some(rest) = key.strip_prefix("five_hour_") {
                    format!("5H {}", title_words(rest))
                } else {
                    title_words(key)
                }
            }
        }
    }

    /// Codex: nhãn theo độ dài cửa sổ (300 phút → 5H, 10080 → 7D).
    pub fn codex(window_minutes: Option<u64>, fallback: &str) -> String {
        match window_minutes {
            Some(m) if m > 0 && m % 1440 == 0 => format!("{}D", m / 1440),
            Some(m) if m > 0 && m % 60 == 0 => format!("{}H", m / 60),
            Some(m) if m > 0 => format!("{m}M"),
            _ => fallback.to_string(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::labels;

    #[test]
    fn label_names() {
        assert_eq!(labels::claude("five_hour"), "5H");
        assert_eq!(labels::claude("seven_day_fable"), "7D Fable");
        assert_eq!(labels::claude("seven_day_oauth_apps"), "7D OAuth Apps");
        assert_eq!(labels::codex(Some(300), "x"), "5H");
        assert_eq!(labels::codex(Some(10080), "x"), "7D");
        assert_eq!(labels::codex(None, "7D"), "7D");
    }
}
