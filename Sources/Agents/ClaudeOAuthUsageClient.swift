// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import AgentKit
import Foundation

/// TÙY CHỌN (mặc định tắt): đọc hạn mức Claude từ `https://api.anthropic.com/api/oauth/usage`
/// bằng token OAuth mà Claude Code lưu trong Keychain ("Claude Code-credentials").
///
/// - Endpoint không có tài liệu chính thức: có thể đổi bất cứ lúc nào → lỗi được báo nhẹ nhàng.
/// - Token được đọc qua `/usr/bin/security` (công cụ của Apple, đã nằm sẵn trong danh sách tin cậy của mục Keychain
///   này) chứ KHÔNG gọi `SecItemCopyMatching` trực tiếp: quyền truy cập theo chữ ký của MacHub mất hiệu lực mỗi
///   lần build/cập nhật (chứng chỉ tự ký → ràng buộc theo cdhash) và macOS lại hỏi mật khẩu Keychain.
/// - Token được giữ trong bộ nhớ đến lúc hết hạn nên không đọc Keychain ở mỗi lần poll.
/// - MacHub KHÔNG tự làm mới token (làm vậy có thể đăng xuất Claude Code). Token hết hạn → nhắc mở Claude Code.
/// - Token chỉ giữ trong bộ nhớ trong lúc gọi, không lưu lại, không gửi đi đâu khác.
enum ClaudeOAuthUsageClient {
    enum FetchError: Error {
        case noCredentials
        case expired
        case keychainDenied
        case http(Int)
        case badResponse
        case network(String)

        var message: String {
            switch self {
            case .noCredentials: return tr("Chưa thấy đăng nhập Claude Code trên máy này.", "No Claude Code login found on this Mac.")
            case .expired: return tr("Token Claude Code đã hết hạn — mở Claude Code một lần để làm mới.", "Claude Code token expired — open Claude Code once to refresh it.")
            case .keychainDenied: return tr("Bạn chưa cho MacHub đọc Keychain của Claude Code.", "Keychain access to Claude Code credentials was denied.")
            case .http(429): return tr("Bị giới hạn tần suất, thử lại sau.", "Rate limited, will retry later.")
            case .http(401), .http(403): return tr("Token bị từ chối — mở Claude Code để đăng nhập lại.", "Token rejected — sign in to Claude Code again.")
            case .http(let code): return tr("Máy chủ trả lỗi \(code).", "Server returned \(code).")
            case .badResponse: return tr("Định dạng phản hồi đã thay đổi.", "Unexpected response format.")
            case .network(let m): return m
            }
        }
    }

    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetch() async -> Swift.Result<LimitSnapshot, FetchError> {
        let token: String
        switch readToken(forceReload: false) {
        case .success(let t): token = t
        case .failure(let e): return .failure(e)
        }
        var req = URLRequest(url: endpoint, timeoutInterval: 15)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("MacHub/\(UpdateManager.currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 || code == 403 { cache.set(nil) }  // Claude Code có thể đã làm mới token: lần sau đọc lại
            guard code == 200 else { return .failure(.http(code)) }
            guard let snap = ClaudeOAuthUsage.parse(data) else { return .failure(.badResponse) }
            return .success(snap)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    /// Token đang giữ trong bộ nhớ; chỉ đọc Keychain lại khi hết hạn hoặc bị máy chủ từ chối.
    private static let cache = TokenCache()

    private final class TokenCache: @unchecked Sendable {
        private let lock = NSLock()
        private var creds: ClaudeCredentials?
        func get() -> ClaudeCredentials? { lock.lock(); defer { lock.unlock() }; return creds }
        func set(_ c: ClaudeCredentials?) { lock.lock(); creds = c; lock.unlock() }
    }

    /// Chạy `/usr/bin/security find-generic-password -s … -w` (không qua shell), tối đa `timeout` giây.
    /// Trả về nội dung stdout hoặc mã thoát: 44 = không có mục; 36/51/128 = bị từ chối/huỷ.
    static func runSecurity(timeout: TimeInterval = 10) -> Swift.Result<Data, FetchError> {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return .failure(.network("security: \(error.localizedDescription)")) }

        // Đọc stdout song song để ống không đầy; quá hạn thì dừng (tránh treo nếu macOS hiện hộp thoại).
        var buf = Data()
        let reader = DispatchGroup()
        reader.enter()
        DispatchQueue.global(qos: .utility).async {
            buf = out.fileHandleForReading.readDataToEndOfFile()
            reader.leave()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if p.isRunning {
            p.terminate()
            reader.wait()
            return .failure(.keychainDenied)
        }
        reader.wait()
        switch p.terminationStatus {
        case 0: return .success(buf)
        case 44: return .failure(.noCredentials)
        default: return .failure(.keychainDenied)
        }
    }

    private static func readToken(forceReload: Bool) -> Swift.Result<String, FetchError> {
        if !forceReload, let c = cache.get(), c.isValid() { return .success(c.accessToken) }
        cache.set(nil)
        switch runSecurity() {
        case .failure(let e): return .failure(e)
        case .success(let data):
            guard let creds = ClaudeCredentials.parse(data) else { return .failure(.noCredentials) }
            guard creds.isValid() else { return .failure(.expired) }
            cache.set(creds)
            return .success(creds.accessToken)
        }
    }
}
