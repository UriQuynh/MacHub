// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

use crate::pricing::{PriceBook, Quote};
use crate::{Provider, UsageRecord};
use chrono::{DateTime, Duration, Local, NaiveDate, Utc};
use serde::Serialize;
use std::collections::{BTreeMap, HashMap};

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Totals {
    pub input: u64,
    pub output: u64,
    pub cache_write: u64,
    pub cache_read: u64,
    pub requests: u64,
    pub cost_usd: f64,
    pub has_estimate: bool,
    pub unpriced_tokens: u64,
    pub total: u64,
}

impl Totals {
    fn add(&mut self, r: &UsageRecord, q: Quote) {
        self.input += r.input_tokens;
        self.output += r.output_tokens;
        self.cache_write += r.cache_write_tokens();
        self.cache_read += r.cache_read_tokens;
        self.requests += 1;
        self.total += r.total_tokens();
        match q.usd {
            Some(u) => {
                self.cost_usd += u;
                self.has_estimate |= q.estimated;
            }
            None => self.unpriced_tokens += r.total_tokens(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Row {
    pub provider: Provider,
    pub name: String,
    pub totals: Totals,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Day {
    pub day: NaiveDate,
    pub tokens: HashMap<Provider, u64>,
    pub cost: HashMap<Provider, f64>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Summary {
    pub by_provider: HashMap<Provider, Totals>,
    pub by_model: Vec<Row>,
    pub by_project: Vec<Row>,
    pub days: Vec<Day>,
}

fn project_name(p: &Option<String>) -> String {
    p.as_deref()
        .map(|s| s.trim_end_matches(['\\', '/']).rsplit(['\\', '/']).next().unwrap_or(s).to_string())
        .unwrap_or_else(|| "—".into())
}

/// Tổng hợp theo nhà cung cấp, model, dự án, ngày (theo giờ máy).
pub fn build(records: &[UsageRecord], from: DateTime<Utc>, to: DateTime<Utc>, prices: &PriceBook) -> Summary {
    build_in(records, from, to, prices, |t| t.with_timezone(&Local).date_naive())
}

pub fn build_in(
    records: &[UsageRecord],
    from: DateTime<Utc>,
    to: DateTime<Utc>,
    prices: &PriceBook,
    day_of: impl Fn(DateTime<Utc>) -> NaiveDate,
) -> Summary {
    let mut by_provider: HashMap<Provider, Totals> = HashMap::new();
    let mut models: HashMap<(Provider, String), Totals> = HashMap::new();
    let mut projects: HashMap<(Provider, String), Totals> = HashMap::new();
    let mut days: BTreeMap<NaiveDate, Day> = BTreeMap::new();

    let (mut d, last) = (day_of(from), day_of(to));
    while d <= last {
        days.insert(d, Day { day: d, tokens: HashMap::new(), cost: HashMap::new() });
        d += Duration::days(1);
    }

    for r in records.iter().filter(|r| r.timestamp >= from && r.timestamp <= to) {
        let q = prices.quote(r);
        by_provider.entry(r.provider).or_default().add(r, q);
        models.entry((r.provider, r.model.clone())).or_default().add(r, q);
        projects.entry((r.provider, project_name(&r.project))).or_default().add(r, q);
        let day = days.entry(day_of(r.timestamp)).or_insert_with(|| Day {
            day: day_of(r.timestamp),
            tokens: HashMap::new(),
            cost: HashMap::new(),
        });
        *day.tokens.entry(r.provider).or_default() += r.total_tokens();
        *day.cost.entry(r.provider).or_default() += q.usd.unwrap_or(0.0);
    }

    let rows = |m: HashMap<(Provider, String), Totals>| {
        let mut v: Vec<Row> = m.into_iter().map(|((provider, name), totals)| Row { provider, name, totals }).collect();
        v.sort_by(|a, b| b.totals.total.cmp(&a.totals.total).then_with(|| a.name.cmp(&b.name)));
        v
    };
    Summary { by_provider, by_model: rows(models), by_project: rows(projects), days: days.into_values().collect() }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    #[test]
    fn totals() {
        let d1 = Utc.with_ymd_and_hms(2026, 11, 17, 3, 0, 0).unwrap();
        let d2 = Utc.with_ymd_and_hms(2026, 11, 18, 16, 0, 0).unwrap();
        let mk = |p, t, m: &str, proj: &str, i, o| {
            let mut r = UsageRecord::new(p, t, m, i, o);
            r.project = Some(proj.into());
            r
        };
        let recs = vec![
            mk(Provider::Claude, d1, "claude-sonnet-4", "C:\\a\\FTL", 100, 10),
            mk(Provider::Claude, d2, "claude-sonnet-4", "C:\\a\\FTL", 100, 10),
            mk(Provider::Codex, d2, "gpt-5.3-codex", "/a/MacHub", 50, 5),
            mk(Provider::Claude, d1, "claude-fable-5-2", "/a/X", 7, 0),
        ];
        let from = Utc.with_ymd_and_hms(2026, 11, 17, 0, 0, 0).unwrap();
        let s = build_in(&recs, from, d2, &PriceBook::default(), |t| t.date_naive());
        assert_eq!(s.by_provider[&Provider::Claude].total, 227);
        assert_eq!(s.by_provider[&Provider::Claude].unpriced_tokens, 7);
        assert_eq!(s.by_provider[&Provider::Codex].total, 55);
        assert_eq!(s.by_model[0].name, "claude-sonnet-4");
        assert_eq!(s.by_project[0].name, "FTL");
        assert_eq!(s.days.len(), 2);
        assert_eq!(s.days[1].tokens[&Provider::Codex], 55);
    }
}
