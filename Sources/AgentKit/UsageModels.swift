// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import Foundation

public enum AgentProvider: String, Codable, CaseIterable, Sendable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }
}

/// Lượng token của MỘT phản hồi model (đã khử trùng lặp).
public struct UsageRecord: Equatable, Sendable {
    public var provider: AgentProvider
    public var timestamp: Date
    public var model: String
    public var project: String?
    public var sessionID: String?
    /// Token đầu vào KHÔNG tính phần đọc từ cache.
    public var inputTokens: Int
    public var outputTokens: Int
    /// Ghi cache (Claude): 5 phút và 1 giờ có giá khác nhau.
    public var cacheWrite5mTokens: Int
    public var cacheWrite1hTokens: Int
    public var cacheReadTokens: Int

    public init(provider: AgentProvider, timestamp: Date, model: String, project: String? = nil, sessionID: String? = nil,
                inputTokens: Int, outputTokens: Int, cacheWrite5mTokens: Int = 0, cacheWrite1hTokens: Int = 0,
                cacheReadTokens: Int = 0) {
        self.provider = provider
        self.timestamp = timestamp
        self.model = model
        self.project = project
        self.sessionID = sessionID
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheWrite5mTokens = cacheWrite5mTokens
        self.cacheWrite1hTokens = cacheWrite1hTokens
        self.cacheReadTokens = cacheReadTokens
    }

    public var cacheWriteTokens: Int { cacheWrite5mTokens + cacheWrite1hTokens }
    public var totalTokens: Int { inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens }
}

/// Một cửa sổ hạn mức (5 giờ, 7 ngày, 7 ngày theo model…).
public struct LimitWindow: Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    /// 0–100.
    public var usedPercent: Double
    public var resetsAt: Date?
    public var windowMinutes: Int?

    public init(id: String, label: String, usedPercent: Double, resetsAt: Date?, windowMinutes: Int? = nil) {
        self.id = id
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowMinutes = windowMinutes
    }
}

public struct LimitSnapshot: Equatable, Sendable {
    public enum Source: String, Sendable {
        case statusLine = "statusLine"
        case oauth = "OAuth"
        case codexLog = "log Codex"
    }

    public var provider: AgentProvider
    public var windows: [LimitWindow]
    public var observedAt: Date
    public var source: Source
    public var plan: String?

    public init(provider: AgentProvider, windows: [LimitWindow], observedAt: Date, source: Source, plan: String? = nil) {
        self.provider = provider
        self.windows = windows
        self.observedAt = observedAt
        self.source = source
        self.plan = plan
    }

    /// Cửa sổ có % cao nhất (để hiện chip tóm tắt).
    public var headline: LimitWindow? { windows.max(by: { $0.usedPercent < $1.usedPercent }) }
}

public enum LimitLabels {
    /// "five_hour" → "5H", "seven_day" → "7D", "seven_day_opus" → "7D Opus".
    public static func claude(_ key: String) -> String {
        switch key {
        case "five_hour": return "5H"
        case "seven_day": return "7D"
        default:
            if key.hasPrefix("seven_day_") {
                let rest = key.dropFirst("seven_day_".count).split(separator: "_").map { $0.capitalized }.joined(separator: " ")
                return "7D \(rest.replacingOccurrences(of: "Oauth", with: "OAuth"))"
            }
            if key.hasPrefix("five_hour_") {
                let rest = key.dropFirst("five_hour_".count).split(separator: "_").map { $0.capitalized }.joined(separator: " ")
                return "5H \(rest)"
            }
            return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Codex: nhãn theo độ dài cửa sổ (300 phút → 5H, 10080 → 7D).
    public static func codex(windowMinutes: Int?, fallback: String) -> String {
        guard let m = windowMinutes, m > 0 else { return fallback }
        if m % 1440 == 0 { return "\(m / 1440)D" }
        if m % 60 == 0 { return "\(m / 60)H" }
        return "\(m)M"
    }
}
