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
        lock.lock()
        defer { lock.unlock() }
        return withFraction.date(from: s) ?? plain.date(from: s)
    }
}
