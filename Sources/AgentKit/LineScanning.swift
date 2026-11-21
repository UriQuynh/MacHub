// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import Foundation

/// Tiện ích byte cho đường quét nhanh: không tạo `String`/`JSONValue` cho dòng không cần.
enum LineBytes {
    /// `needle` có nằm trong `haystack` không (so khớp byte, không cấp phát).
    static func contains(_ haystack: UnsafeRawBufferPointer, needle: [UInt8]) -> Bool {
        guard let base = haystack.baseAddress, !needle.isEmpty, haystack.count >= needle.count else { return false }
        return needle.withUnsafeBytes { n in memmem(base, haystack.count, n.baseAddress!, n.count) != nil }
    }

    /// Giống `JSONValue.int` nhưng không sập khi số quá lớn/không hữu hạn (coi như 0).
    static func tokenCount(_ d: Double?) -> Int {
        guard let d, d.isFinite, abs(d) < 9.0e18 else { return 0 }
        return Int(d)
    }
}

extension KeyedDecodingContainer {
    /// Chuỗi nếu đúng là chuỗi JSON; thiếu khóa / null / sai kiểu → nil (giống `JSONValue.string`).
    func lenientString(_ key: Key) -> String? { try? decode(String.self, forKey: key) }

    /// Số nếu là số JSON hoặc chuỗi số (giống `JSONValue.double`); còn lại → nil.
    func lenientDouble(_ key: Key) -> Double? {
        if let d = try? decode(Double.self, forKey: key) { return d }
        if let s = try? decode(String.self, forKey: key) { return Double(s) }
        return nil
    }

    /// Đối tượng JSON giải mã được thành `T`; thiếu khóa / null / không phải object → nil.
    func lenientObject<T: Decodable>(_ key: Key, as type: T.Type = T.self) -> T? { try? decode(T.self, forKey: key) }
}

/// Các trường của một dòng transcript Claude Code mà bộ quét cần; mọi trường khác bị bỏ qua khi giải mã.
struct LineProbe: Decodable {
    var type: String?
    var timestamp: String?
    var cwd: String?
    var sessionId: String?
    var requestId: String?
    var message: Message?

    struct Message: Decodable {
        var id: String?
        var model: String?
        var usage: Usage?

        enum CodingKeys: String, CodingKey { case id, model, usage }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.lenientString(.id)
            model = c.lenientString(.model)
            usage = c.lenientObject(.usage)
        }
    }

    struct Usage: Decodable {
        var input: Double?
        var output: Double?
        var cacheRead: Double?
        var cacheCreation: Double?
        var detail: Detail?

        struct Detail: Decodable {
            var five: Double?
            var hour: Double?
            enum CodingKeys: String, CodingKey {
                case five = "ephemeral_5m_input_tokens", hour = "ephemeral_1h_input_tokens"
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                five = c.lenientDouble(.five)
                hour = c.lenientDouble(.hour)
            }
        }

        enum CodingKeys: String, CodingKey {
            case input = "input_tokens", output = "output_tokens", cacheRead = "cache_read_input_tokens"
            case cacheCreation = "cache_creation_input_tokens", detail = "cache_creation"
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            input = c.lenientDouble(.input)
            output = c.lenientDouble(.output)
            cacheRead = c.lenientDouble(.cacheRead)
            cacheCreation = c.lenientDouble(.cacheCreation)
            detail = c.lenientObject(.detail)
        }
    }

    enum CodingKeys: String, CodingKey { case type, timestamp, cwd, sessionId, requestId, message }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = c.lenientString(.type)
        timestamp = c.lenientString(.timestamp)
        cwd = c.lenientString(.cwd)
        sessionId = c.lenientString(.sessionId)
        requestId = c.lenientString(.requestId)
        message = c.lenientObject(.message)
    }
}

/// Một dòng rollout Codex: `timestamp`, `type` và (chỉ khi thật sự được dùng) `payload`.
struct CodexLineProbe: Decodable {
    var timestamp: String?
    var type: String?
    var payload: JSONValue?

    private struct PayloadHead: Decodable {
        var type: String?
        enum CodingKeys: String, CodingKey { case type }
        init(from decoder: Decoder) throws {
            type = try decoder.container(keyedBy: CodingKeys.self).lenientString(.type)
        }
    }

    enum CodingKeys: String, CodingKey { case timestamp, type, payload }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = c.lenientString(.timestamp)
        type = c.lenientString(.type)
        switch type {
        case "session_meta", "turn_context":
            payload = try? c.decode(JSONValue.self, forKey: .payload)
        case "event_msg":
            // Chỉ dựng cây payload cho loại sự kiện thật sự được xử lý (bỏ qua đầu ra lệnh, lý luận… có thể rất lớn).
            if let head = try? c.decode(PayloadHead.self, forKey: .payload), let t = head.type,
               CodexRolloutAccumulator.handledEventTypes.contains(t) {
                payload = try? c.decode(JSONValue.self, forKey: .payload)
            }
        default:
            break
        }
    }
}
