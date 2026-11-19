// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

//! Bảng giá ước tính THEO GIÁ API (USD / 1 triệu token). Cùng quy tắc với bản macOS.

use crate::UsageRecord;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct ModelPrice {
    pub input: f64,
    pub output: f64,
    #[serde(rename = "cacheWrite5m", default)]
    pub cache_write_5m: Option<f64>,
    #[serde(rename = "cacheWrite1h", default)]
    pub cache_write_1h: Option<f64>,
    #[serde(rename = "cacheRead", default)]
    pub cache_read: Option<f64>,
}

impl ModelPrice {
    pub const fn new(input: f64, output: f64) -> Self {
        ModelPrice { input, output, cache_write_5m: None, cache_write_1h: None, cache_read: None }
    }

    pub const fn with_cached(input: f64, output: f64, cached: f64) -> Self {
        ModelPrice { input, output, cache_write_5m: None, cache_write_1h: None, cache_read: Some(cached) }
    }

    pub fn cost(&self, r: &UsageRecord) -> f64 {
        let w5 = self.cache_write_5m.unwrap_or(self.input * 1.25);
        let w1 = self.cache_write_1h.unwrap_or(self.input * 2.0);
        let rd = self.cache_read.unwrap_or(self.input * 0.1);
        (r.input_tokens as f64 * self.input
            + r.output_tokens as f64 * self.output
            + r.cache_write_5m_tokens as f64 * w5
            + r.cache_write_1h_tokens as f64 * w1
            + r.cache_read_tokens as f64 * rd)
            / 1_000_000.0
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Quote {
    pub usd: Option<f64>,
    /// true khi lấy giá theo dòng model (≈), không khớp chính xác.
    pub estimated: bool,
}

#[derive(Debug, Clone)]
pub struct PriceBook {
    pub exact: HashMap<String, ModelPrice>,
    pub families: Vec<(String, ModelPrice)>,
}

impl Default for PriceBook {
    fn default() -> Self {
        let exact = [
            ("opus-4-5", ModelPrice::new(5.0, 25.0)),
            ("opus-4-1", ModelPrice::new(15.0, 75.0)),
            ("opus-4", ModelPrice::new(15.0, 75.0)),
            ("sonnet-4", ModelPrice::new(3.0, 15.0)),
            ("3-7-sonnet", ModelPrice::new(3.0, 15.0)),
            ("3-5-sonnet", ModelPrice::new(3.0, 15.0)),
            ("haiku-4-5", ModelPrice::new(1.0, 5.0)),
            ("3-5-haiku", ModelPrice::new(0.8, 4.0)),
            ("gpt-5-codex", ModelPrice::with_cached(1.25, 10.0, 0.125)),
            ("gpt-5.1-codex", ModelPrice::with_cached(1.25, 10.0, 0.125)),
            ("gpt-5.1", ModelPrice::with_cached(1.25, 10.0, 0.125)),
            ("gpt-5.2-codex", ModelPrice::with_cached(1.75, 14.0, 0.175)),
            ("gpt-5.2", ModelPrice::with_cached(1.75, 14.0, 0.175)),
            ("gpt-5.3-codex", ModelPrice::with_cached(1.75, 14.0, 0.175)),
            ("gpt-5.4", ModelPrice::with_cached(2.5, 15.0, 0.25)),
            ("gpt-5-mini", ModelPrice::with_cached(0.25, 2.0, 0.025)),
            ("gpt-5-nano", ModelPrice::with_cached(0.05, 0.4, 0.005)),
            ("gpt-5", ModelPrice::with_cached(1.25, 10.0, 0.125)),
        ]
        .into_iter()
        .map(|(k, v)| (k.to_string(), v))
        .collect();
        // Dài trước để "gpt-5" không che mất tên dài hơn.
        let families = vec![
            ("sonnet".to_string(), ModelPrice::new(3.0, 15.0)),
            ("haiku".to_string(), ModelPrice::new(1.0, 5.0)),
            ("gpt-5".to_string(), ModelPrice::with_cached(1.75, 14.0, 0.175)),
            ("opus".to_string(), ModelPrice::new(5.0, 25.0)),
        ];
        PriceBook { exact, families }
    }
}

impl PriceBook {
    pub fn normalize(model: &str) -> String {
        let mut m = model.to_lowercase();
        if let Some(rest) = m.strip_prefix("claude-") {
            m = rest.to_string();
        }
        if m.ends_with("[1m]") {
            m.truncate(m.len() - 4);
        }
        // hậu tố ngày -YYYYMMDD
        if m.len() > 9 {
            let (head, tail) = m.split_at(m.len() - 9);
            if tail.starts_with('-') && tail[1..].chars().all(|c| c.is_ascii_digit()) {
                m = head.to_string();
            }
        }
        m
    }

    /// `key` khớp khi bằng nhau, hoặc model = key + "-<hậu tố không bắt đầu bằng số>".
    /// "opus-4" không khớp "opus-4-6"; "gpt-5" không khớp "gpt-5.5".
    pub fn matches(model: &str, key: &str) -> bool {
        if model == key {
            return true;
        }
        let Some(rest) = model.strip_prefix(key) else { return false };
        let mut c = rest.chars();
        c.next() == Some('-') && c.next().is_some_and(|n| !n.is_ascii_digit())
    }

    pub fn price(&self, model: &str) -> Option<(ModelPrice, bool)> {
        let m = Self::normalize(model);
        if let Some(k) = self.exact.keys().filter(|k| Self::matches(&m, k)).max_by_key(|k| k.len()) {
            return Some((self.exact[k], false));
        }
        let mut fams: Vec<&(String, ModelPrice)> = self.families.iter().collect();
        fams.sort_by_key(|(k, _)| std::cmp::Reverse(k.len()));
        fams.into_iter().find(|(k, _)| m.contains(k.as_str())).map(|(_, p)| (*p, true))
    }

    pub fn quote(&self, r: &UsageRecord) -> Quote {
        match self.price(&r.model) {
            Some((p, est)) => Quote { usd: Some(p.cost(r)), estimated: est },
            None => Quote { usd: None, estimated: false },
        }
    }

    /// `pricing.json`: `{"models": {"claude-fable-5-2": {"input": 10, "output": 50}}, "families": {...}}`.
    pub fn apply_overrides(&mut self, path: &Path) {
        #[derive(Deserialize)]
        struct Overrides {
            models: Option<HashMap<String, ModelPrice>>,
            families: Option<HashMap<String, ModelPrice>>,
        }
        let Ok(text) = std::fs::read_to_string(path) else { return };
        let Ok(o) = serde_json::from_str::<Overrides>(&text) else { return };
        for (k, v) in o.models.unwrap_or_default() {
            self.exact.insert(Self::normalize(&k), v);
        }
        for (k, v) in o.families.unwrap_or_default() {
            let k = k.to_lowercase();
            self.families.retain(|(f, _)| *f != k);
            self.families.push((k, v));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Provider;
    use chrono::Utc;

    #[test]
    fn normalize() {
        assert_eq!(PriceBook::normalize("claude-sonnet-4-20250514"), "sonnet-4");
        assert_eq!(PriceBook::normalize("claude-opus-4-5-20251101"), "opus-4-5");
        assert_eq!(PriceBook::normalize("claude-sonnet-5-5[1m]"), "sonnet-5-5");
    }

    #[test]
    fn exact_match_does_not_leak_across_versions() {
        let b = PriceBook::default();
        assert_eq!(b.price("claude-opus-4-5-20251101").unwrap(), (ModelPrice::new(5.0, 25.0), false));
        assert!(b.price("claude-opus-4-6").unwrap().1);
        assert!(b.price("gpt-5.5").unwrap().1);
        let max = b.price("gpt-5.1-codex-max").unwrap();
        assert!(!max.1);
        assert_eq!(max.0.output, 10.0);
        assert!(b.price("claude-fable-5-2").is_none());
    }

    #[test]
    fn costs() {
        let b = PriceBook::default();
        let mut r = UsageRecord::new(Provider::Claude, Utc::now(), "claude-sonnet-4-20250514", 1_000_000, 1_000_000);
        r.cache_write_5m_tokens = 1_000_000;
        r.cache_write_1h_tokens = 1_000_000;
        r.cache_read_tokens = 1_000_000;
        assert!((b.quote(&r).usd.unwrap() - (3.0 + 15.0 + 3.75 + 6.0 + 0.3)).abs() < 1e-9);
        let mut c = UsageRecord::new(Provider::Codex, Utc::now(), "gpt-5.3-codex", 1_000_000, 0);
        c.cache_read_tokens = 1_000_000;
        assert!((b.quote(&c).usd.unwrap() - 1.925).abs() < 1e-9);
    }

    #[test]
    fn overrides() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("pricing.json");
        std::fs::write(&p, r#"{"models":{"claude-fable-5-2":{"input":10,"output":50}}}"#).unwrap();
        let mut b = PriceBook::default();
        b.apply_overrides(&p);
        assert_eq!(b.price("claude-fable-5-2").unwrap(), (ModelPrice::new(10.0, 50.0), false));
    }
}
