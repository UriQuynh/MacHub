// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import CryptoKit
import Foundation
import Security

/// Mã hóa dữ liệu lưu trên đĩa (lịch sử clipboard, ảnh clipboard) bằng AES-256-GCM.
///
/// - Khóa 256-bit sinh ngẫu nhiên một lần, lưu trong Keychain đăng nhập với
///   `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (không đồng bộ iCloud, không vào bản sao lưu máy khác).
/// - Định dạng file: `"MHE1"` + `nonce(12) | ciphertext | tag(16)` (AES.GCM combined).
/// - File cũ không có header được coi là bản rõ của HyperMac và được đọc bình thường để chuyển đổi;
///   lần ghi kế tiếp sẽ mã hóa lại.
enum SecureStore {
    private static let magic = Data("MHE1".utf8)
    private static let service = "com.machub.app.storage-key"
    private static let account = "clipboard-v1"

    enum StoreError: Error {
        case keyUnavailable(OSStatus)
        case malformed
    }

    // MARK: - Public API

    /// Mã hóa rồi ghi atomic, quyền file 0600.
    static func write(_ plaintext: Data, to url: URL) throws {
        let sealed = try AES.GCM.seal(plaintext, using: try key())
        guard let combined = sealed.combined else { throw StoreError.malformed }
        try (magic + combined).write(to: url, options: .atomic)
        restrictPermissions(url, mode: 0o600)
    }

    /// Đọc và giải mã. File không có header `MHE1` (bản rõ cũ) được trả về nguyên trạng.
    static func read(from url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        return try open(data)
    }

    static func open(_ data: Data) throws -> Data {
        guard data.starts(with: magic) else { return data }
        let box = try AES.GCM.SealedBox(combined: data.dropFirst(magic.count))
        return try AES.GCM.open(box, using: try key())
    }

    static func isEncrypted(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: magic.count)) == magic
    }

    /// Thư mục dữ liệu riêng tư (0700).
    static func ensurePrivateDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        restrictPermissions(url, mode: 0o700)
    }

    static func restrictPermissions(_ url: URL, mode: Int) {
        try? FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    // MARK: - Key management

    private static let keyLock = NSLock()
    private static var cachedKey: SymmetricKey?  // chỉ truy cập trong keyLock

    private static func key() throws -> SymmetricKey {
        keyLock.lock()
        defer { keyLock.unlock() }
        if let cachedKey { return cachedKey }

        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess, let data = item as? Data, data.count == 32 {
            let key = SymmetricKey(data: data)
            cachedKey = key
            return key
        }
        guard status == errSecItemNotFound else {
            // Keychain khóa / bị từ chối: không tạo khóa mới (sẽ làm mất dữ liệu cũ), báo lỗi để caller bỏ qua lần lưu này.
            throw StoreError.keyUnavailable(status)
        }

        let newKey = SymmetricKey(size: .bits256)
        var add = base
        add[kSecValueData as String] = newKey.withUnsafeBytes { Data($0) }
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecAttrLabel as String] = "MacHub storage key"
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw StoreError.keyUnavailable(addStatus) }
        cachedKey = newKey
        return newKey
    }
}
