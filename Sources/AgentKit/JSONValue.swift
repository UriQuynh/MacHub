// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import Foundation

/// Giá trị JSON bất kỳ, dùng để chuyển nguyên vẹn payload hook / transcript mà không cần mô hình hóa hết.
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Giá trị JSON không hợp lệ")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    // MARK: Truy cập tiện lợi

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    /// Đi theo đường dẫn khóa, vd. `value.path("message", "usage", "input_tokens")`.
    public func path(_ keys: String...) -> JSONValue? {
        var cur: JSONValue? = self
        for k in keys { cur = cur?[k] }
        return cur
    }

    public var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var double: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s)
        default: return nil
        }
    }

    public var int: Int? { double.map { Int($0) } }

    public var bool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var object: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    public var array: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    // MARK: Chuyển đổi

    public static func parse(_ data: Data) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    public static func parse(_ line: String) -> JSONValue? {
        parse(Data(line.utf8))
    }

    public func encoded(sortedKeys: Bool = true) -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = sortedKeys ? [.sortedKeys, .withoutEscapingSlashes] : [.withoutEscapingSlashes]
        return (try? enc.encode(self)) ?? Data("null".utf8)
    }

    public var compactString: String {
        String(decoding: encoded(), as: UTF8.self)
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByFloatLiteral,
    ExpressibleByIntegerLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
    public init(nilLiteral: ()) { self = .null }
}

/// Ngày giờ ISO 8601 có/không phần lẻ giây (định dạng của transcript Claude Code và Codex).
public enum ISODate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let lock = NSLock()

    public static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        if let d = parseFast(s) { return d }
        return parseWithFormatters(s)
    }

    /// Đường chậm (và là chuẩn đối chiếu): `ISO8601DateFormatter`, qua ICU, vài micro-giây mỗi lần.
    static func parseWithFormatters(_ s: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return withFraction.date(from: s) ?? plain.date(from: s)
    }

    /// Đường nhanh cho đúng hai dạng Claude Code / Codex ghi ra: `YYYY-MM-DDTHH:MM:SSZ` và `YYYY-MM-DDTHH:MM:SS.mmmZ`
    /// (UTC). Cho cùng `Date` với `parseWithFormatters` (test so khớp từng giá trị). Dạng khác, hoặc ngày giờ không hợp lệ
    /// (tháng 13, 30/2, giờ 24…) → nil để rơi về formatter, giữ nguyên hành vi cũ ở các ca lạ.
    static func parseFast(_ s: String) -> Date? {
        s.utf8.withContiguousStorageIfAvailable { p -> Date? in
            guard p.count == 20 || p.count == 24 else { return nil }
            func digit(_ i: Int) -> Int? {
                let c = Int(p[i]) - 48
                return (0...9).contains(c) ? c : nil
            }
            func num(_ i: Int, _ n: Int) -> Int? {
                var v = 0
                for k in i..<(i + n) {
                    guard let d = digit(k) else { return nil }
                    v = v * 10 + d
                }
                return v
            }
            guard p[4] == 0x2D, p[7] == 0x2D, p[10] == 0x54, p[13] == 0x3A, p[16] == 0x3A, p[p.count - 1] == 0x5A,
                  let y = num(0, 4), let mo = num(5, 2), let d = num(8, 2),
                  let h = num(11, 2), let mi = num(14, 2), let sec = num(17, 2),
                  (1970...2200).contains(y), (1...12).contains(mo), h <= 23, mi <= 59, sec <= 59 else { return nil }
            var ms = 0
            if p.count == 24 {
                guard p[19] == 0x2E, let f = num(20, 3) else { return nil }
                ms = f
            }
            let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
            let dim = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][mo - 1]
            guard (1...dim).contains(d) else { return nil }
            // Số ngày từ 1970-01-01 (thuật toán days-from-civil).
            let yy = mo <= 2 ? y - 1 : y
            let era = yy / 400
            let yoe = yy - era * 400
            let doy = (153 * (mo + (mo > 2 ? -3 : 9)) + 2) / 5 + d - 1
            let days = era * 146_097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719_468
            let whole = days * 86_400 + h * 3_600 + mi * 60 + sec
            return Date(timeIntervalSince1970: Double(whole) + Double(ms) / 1000)
        } ?? nil
    }
}
