// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import AgentKit
import Foundation
import Security

/// TÙY CHỌN (mặc định tắt): đọc hạn mức Claude từ `https://api.anthropic.com/api/oauth/usage`
/// bằng token OAuth mà Claude Code lưu trong Keychain ("Claude Code-credentials").
///
/// - Endpoint không có tài liệu chính thức: có thể đổi bất cứ lúc nào → lỗi được báo nhẹ nhàng.
/// - Lần đầu, macOS hỏi bạn có cho MacHub đọc mục Keychain này không.
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
        switch readToken() {
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
            guard code == 200 else { return .failure(.http(code)) }
            guard let snap = ClaudeOAuthUsage.parse(data) else { return .failure(.badResponse) }
            return .success(snap)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    private static func readToken() -> Swift.Result<String, FetchError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess: break
        case errSecItemNotFound: return .failure(.noCredentials)
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed: return .failure(.keychainDenied)
        default: return .failure(.network("Keychain \(status)"))
        }
        guard let data = item as? Data, let json = JSONValue.parse(data),
              let oauth = json["claudeAiOauth"], let token = oauth["accessToken"]?.string, !token.isEmpty else {
            return .failure(.noCredentials)
        }
        if let exp = oauth["expiresAt"]?.double, Date(timeIntervalSince1970: exp / 1000) < Date() {
            return .failure(.expired)
        }
        return .success(token)
    }
}
