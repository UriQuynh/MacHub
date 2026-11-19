// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import Foundation

/// Tổng hợp token & chi phí trong một khoảng thời gian.
public struct UsageSummary: Equatable, Sendable {
    public struct Totals: Equatable, Sendable {
        public var input = 0
        public var output = 0
        public var cacheWrite = 0
        public var cacheRead = 0
        public var requests = 0
        public var costUSD = 0.0
        /// Có phần chi phí tính theo giá dòng model (≈).
        public var hasEstimate = false
        /// Token của model chưa có giá (không cộng vào chi phí).
        public var unpricedTokens = 0

        public var total: Int { input + output + cacheWrite + cacheRead }

        public init() {}

        mutating func add(_ r: UsageRecord, _ q: PriceBook.Quote) {
            input += r.inputTokens
            output += r.outputTokens
            cacheWrite += r.cacheWriteTokens
            cacheRead += r.cacheReadTokens
            requests += 1
            if let usd = q.usd {
                costUSD += usd
                if q.estimated { hasEstimate = true }
            } else {
                unpricedTokens += r.totalTokens
            }
        }
    }

    public struct Row: Equatable, Sendable, Identifiable {
        public var id: String { "\(provider.rawValue):\(name)" }
        public var provider: AgentProvider
        public var name: String
        public var totals: Totals
    }

    public struct Day: Equatable, Sendable, Identifiable {
        public var id: Date { day }
        public var day: Date
        public var tokens: [AgentProvider: Int]
        public var cost: [AgentProvider: Double]
    }

    public var from: Date
    public var to: Date
    public var byProvider: [AgentProvider: Totals] = [:]
    public var byModel: [Row] = []
    public var byProject: [Row] = []
    public var days: [Day] = []

    public var overall: Totals {
        byProvider.values.reduce(into: Totals()) { acc, t in
            acc.input += t.input; acc.output += t.output; acc.cacheWrite += t.cacheWrite; acc.cacheRead += t.cacheRead
            acc.requests += t.requests; acc.costUSD += t.costUSD; acc.unpricedTokens += t.unpricedTokens
            acc.hasEstimate = acc.hasEstimate || t.hasEstimate
        }
    }

    public static func build(records: [UsageRecord], from: Date, to: Date, prices: PriceBook,
                             calendar: Calendar = .current) -> UsageSummary {
        var s = UsageSummary(from: from, to: to)
        var models: [String: Row] = [:]
        var projects: [String: Row] = [:]
        var days: [Date: Day] = [:]

        var dayCursor = calendar.startOfDay(for: from)
        let lastDay = calendar.startOfDay(for: to)
        while dayCursor <= lastDay {
            days[dayCursor] = Day(day: dayCursor, tokens: [:], cost: [:])
            guard let next = calendar.date(byAdding: .day, value: 1, to: dayCursor) else { break }
            dayCursor = next
        }

        for r in records where r.timestamp >= from && r.timestamp <= to {
            let q = prices.quote(r)
            s.byProvider[r.provider, default: Totals()].add(r, q)

            let mKey = "\(r.provider.rawValue):\(r.model)"
            models[mKey, default: Row(provider: r.provider, name: r.model, totals: Totals())].totals.add(r, q)

            let pName = r.project.map { ($0 as NSString).lastPathComponent } ?? "—"
            let pKey = "\(r.provider.rawValue):\(pName)"
            projects[pKey, default: Row(provider: r.provider, name: pName, totals: Totals())].totals.add(r, q)

            let d = calendar.startOfDay(for: r.timestamp)
            var day = days[d] ?? Day(day: d, tokens: [:], cost: [:])
            day.tokens[r.provider, default: 0] += r.totalTokens
            day.cost[r.provider, default: 0] += q.usd ?? 0
            days[d] = day
        }

        s.byModel = models.values.sorted { $0.totals.total > $1.totals.total }
        s.byProject = projects.values.sorted { $0.totals.total > $1.totals.total }
        s.days = days.values.sorted { $0.day < $1.day }
        return s
    }
}

public enum UsageFormat {
    /// 1234 → "1,2K", 3_400_000 → "3,4M".
    public static func tokens(_ n: Int) -> String {
        let v = Double(n)
        func f(_ x: Double, _ unit: String) -> String {
            let s = x >= 100 ? String(format: "%.0f", x) : String(format: "%.1f", x)
            return s.replacingOccurrences(of: ".0", with: "").replacingOccurrences(of: ".", with: ",") + unit
        }
        switch v {
        case 1_000_000_000...: return f(v / 1_000_000_000, "B")
        case 1_000_000...: return f(v / 1_000_000, "M")
        case 1_000...: return f(v / 1_000, "K")
        default: return "\(n)"
        }
    }

    public static func usd(_ v: Double) -> String {
        if v == 0 { return "$0" }
        if v < 0.01 { return "<$0,01" }
        return "$" + String(format: v >= 100 ? "%.0f" : "%.2f", v).replacingOccurrences(of: ".", with: ",")
    }

    /// Thời gian còn lại kiểu "3g 9ph", "4ngày 13g", "12ph".
    public static func countdown(to date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let s = Int(date.timeIntervalSince(now))
        if s <= 0 { return "đã reset" }
        let d = s / 86_400, h = (s % 86_400) / 3_600, m = (s % 3_600) / 60
        if d > 0 { return h > 0 ? "\(d)ngày \(h)g" : "\(d)ngày" }
        if h > 0 { return m > 0 ? "\(h)g \(m)ph" : "\(h)g" }
        return "\(max(1, m))ph"
    }

    /// Thời gian đã qua kiểu "14m", "1h", "2d".
    public static func elapsed(since date: Date, now: Date = Date()) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60 { return "\(s)s" }
        if s < 3_600 { return "\(s / 60)m" }
        if s < 86_400 { return "\(s / 3_600)h" }
        return "\(s / 86_400)d"
    }
}
