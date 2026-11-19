// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import Foundation

/// Giá USD cho 1 triệu token.
public struct ModelPrice: Codable, Equatable, Sendable {
    public var input: Double
    public var output: Double
    /// Ghi cache 5 phút (mặc định 1.25× input — quy tắc giá cache của Anthropic).
    public var cacheWrite5m: Double?
    /// Ghi cache 1 giờ (mặc định 2× input).
    public var cacheWrite1h: Double?
    /// Đọc cache (Anthropic mặc định 0.1× input; OpenAI ghi rõ "cached input").
    public var cacheRead: Double?

    public init(input: Double, output: Double, cacheWrite5m: Double? = nil, cacheWrite1h: Double? = nil, cacheRead: Double? = nil) {
        self.input = input
        self.output = output
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
        self.cacheRead = cacheRead
    }

    func cost(_ r: UsageRecord) -> Double {
        let m: Double = 1_000_000
        let write5m: Double = cacheWrite5m ?? input * 1.25
        let write1h: Double = cacheWrite1h ?? input * 2
        let read: Double = cacheRead ?? input * 0.1
        var usd: Double = Double(r.inputTokens) * input
        usd += Double(r.outputTokens) * output
        usd += Double(r.cacheWrite5mTokens) * write5m
        usd += Double(r.cacheWrite1hTokens) * write1h
        usd += Double(r.cacheReadTokens) * read
        return usd / m
    }
}

/// Bảng giá ước tính chi phí THEO GIÁ API (gói thuê bao như Claude Max / ChatGPT Plus không tính theo token).
///
/// - Khớp theo tiền tố dài nhất của id model đã chuẩn hóa (bỏ `claude-`, bỏ hậu tố ngày `-20250514`).
/// - Model mới chưa có giá chính xác: dùng giá của dòng model (opus / sonnet / haiku / gpt-5…) và đánh dấu "ước lượng".
/// - Người dùng ghi đè bằng `~/Library/Application Support/MacHub/pricing.json`:
///   `{"models": {"sonnet-5": {"input": 3, "output": 15}}}`
public struct PriceBook: Sendable {
    public struct Quote: Equatable, Sendable {
        public var usd: Double?
        /// true khi giá lấy theo dòng model, không khớp chính xác.
        public var estimated: Bool
    }

    public private(set) var exact: [String: ModelPrice]
    public private(set) var families: [String: ModelPrice]

    public init(exact: [String: ModelPrice] = PriceBook.defaultExact, families: [String: ModelPrice] = PriceBook.defaultFamilies) {
        self.exact = exact
        self.families = families
    }

    /// Giá niêm yết đã biết (USD / 1M token). Kiểm tra lại trang giá khi có model mới.
    public static let defaultExact: [String: ModelPrice] = [
        // Anthropic
        "opus-4-5": ModelPrice(input: 5, output: 25),
        "opus-4-1": ModelPrice(input: 15, output: 75),
        "opus-4": ModelPrice(input: 15, output: 75),
        "sonnet-4": ModelPrice(input: 3, output: 15),
        "3-7-sonnet": ModelPrice(input: 3, output: 15),
        "3-5-sonnet": ModelPrice(input: 3, output: 15),
        "haiku-4-5": ModelPrice(input: 1, output: 5),
        "3-5-haiku": ModelPrice(input: 0.8, output: 4),
        // OpenAI (input / cached input / output)
        "gpt-5-codex": ModelPrice(input: 1.25, output: 10, cacheRead: 0.125),
        "gpt-5.1-codex": ModelPrice(input: 1.25, output: 10, cacheRead: 0.125),
        "gpt-5.1": ModelPrice(input: 1.25, output: 10, cacheRead: 0.125),
        "gpt-5.2-codex": ModelPrice(input: 1.75, output: 14, cacheRead: 0.175),
        "gpt-5.2": ModelPrice(input: 1.75, output: 14, cacheRead: 0.175),
        "gpt-5.3-codex": ModelPrice(input: 1.75, output: 14, cacheRead: 0.175),
        "gpt-5.4": ModelPrice(input: 2.5, output: 15, cacheRead: 0.25),
        "gpt-5-mini": ModelPrice(input: 0.25, output: 2, cacheRead: 0.025),
        "gpt-5-nano": ModelPrice(input: 0.05, output: 0.4, cacheRead: 0.005),
        "gpt-5": ModelPrice(input: 1.25, output: 10, cacheRead: 0.125),
    ]

    /// Giá theo dòng model, chỉ dùng khi không khớp chính xác (kết quả được đánh dấu ≈).
    public static let defaultFamilies: [String: ModelPrice] = [
        "opus": ModelPrice(input: 5, output: 25),
        "sonnet": ModelPrice(input: 3, output: 15),
        "haiku": ModelPrice(input: 1, output: 5),
        "gpt-5": ModelPrice(input: 1.75, output: 14, cacheRead: 0.175),
    ]

    public static func normalize(_ model: String) -> String {
        var m = model.lowercased()
        if m.hasPrefix("claude-") { m.removeFirst("claude-".count) }
        if let r = m.range(of: #"-\d{8}$"#, options: .regularExpression) { m.removeSubrange(r) }
        if m.hasSuffix("[1m]") { m.removeLast(4) }
        return m
    }

    public func price(for model: String) -> (ModelPrice, estimated: Bool)? {
        let m = PriceBook.normalize(model)
        if let key = exact.keys.filter({ PriceBook.matches(m, key: $0) }).max(by: { $0.count < $1.count }) {
            return (exact[key]!, false)
        }
        for (family, p) in families.sorted(by: { $0.key.count > $1.key.count }) where m.contains(family) {
            return (p, true)
        }
        return nil
    }

    /// `key` khớp `model` khi bằng nhau, hoặc model = key + "-<hậu tố không phải số phiên bản>".
    /// Vd. "gpt-5.1-codex" khớp "gpt-5.1-codex-max", nhưng "opus-4" KHÔNG khớp "opus-4-6"
    /// và "gpt-5" KHÔNG khớp "gpt-5.5" (đó là phiên bản khác, có thể khác giá).
    static func matches(_ model: String, key: String) -> Bool {
        if model == key { return true }
        guard model.hasPrefix(key) else { return false }
        let rest = model.dropFirst(key.count)
        guard rest.first == "-", let next = rest.dropFirst().first else { return false }
        return !next.isNumber
    }

    public func quote(_ r: UsageRecord) -> Quote {
        guard let (p, est) = price(for: r.model) else { return Quote(usd: nil, estimated: false) }
        return Quote(usd: p.cost(r), estimated: est)
    }

    /// Nạp file ghi đè của người dùng (nếu có). Khóa trùng → giá người dùng thắng.
    public mutating func applyOverrides(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(Overrides.self, from: data) else { return }
        for (k, v) in file.models ?? [:] { exact[PriceBook.normalize(k)] = v }
        for (k, v) in file.families ?? [:] { families[k.lowercased()] = v }
    }

    struct Overrides: Decodable {
        var models: [String: ModelPrice]?
        var families: [String: ModelPrice]?
    }
}
