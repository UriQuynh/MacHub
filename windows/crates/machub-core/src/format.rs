// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

use chrono::{DateTime, Utc};

/// 1234 → "1,2K", 3_400_000 → "3,4M".
pub fn tokens(n: u64) -> String {
    let v = n as f64;
    let f = |x: f64, unit: &str| {
        let s = if x >= 100.0 { format!("{x:.0}") } else { format!("{x:.1}") };
        s.trim_end_matches(".0").replace('.', ",") + unit
    };
    match v {
        v if v >= 1e9 => f(v / 1e9, "B"),
        v if v >= 1e6 => f(v / 1e6, "M"),
        v if v >= 1e3 => f(v / 1e3, "K"),
        _ => n.to_string(),
    }
}

/// "3g 9ph", "4ngày 13g", "12ph", "đã reset".
pub fn countdown(to: Option<DateTime<Utc>>, now: DateTime<Utc>) -> Option<String> {
    let s = (to? - now).num_seconds();
    if s <= 0 {
        return Some("đã reset".into());
    }
    let (d, h, m) = (s / 86_400, (s % 86_400) / 3_600, (s % 3_600) / 60);
    Some(if d > 0 {
        if h > 0 { format!("{d}ngày {h}g") } else { format!("{d}ngày") }
    } else if h > 0 {
        if m > 0 { format!("{h}g {m}ph") } else { format!("{h}g") }
    } else {
        format!("{}ph", m.max(1))
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Duration;

    #[test]
    fn formats() {
        assert_eq!(tokens(950), "950");
        assert_eq!(tokens(1_234), "1,2K");
        assert_eq!(tokens(3_400_000), "3,4M");
        assert_eq!(tokens(120_000), "120K");
        assert_eq!(tokens(2_000), "2K");
        let now = Utc::now();
        assert_eq!(countdown(Some(now + Duration::seconds(3 * 3600 + 9 * 60)), now).unwrap(), "3g 9ph");
        assert_eq!(countdown(Some(now + Duration::seconds(4 * 86400 + 13 * 3600)), now).unwrap(), "4ngày 13g");
        assert_eq!(countdown(Some(now - Duration::seconds(5)), now).unwrap(), "đã reset");
    }
}
