// SPDX-License-Identifier: GPL-3.0-only
// MacHub — fork of HyperMac. Original work Copyright (C) 2026 Nguyễn Khắc Đại.
// Modifications Copyright (C) 2026 MacHub contributors.

import Foundation

/// Đường dẫn log: `~/Library/Logs/MacHub/machub.log` (quyền 0600).
///
/// HyperMac ghi vào `/tmp/displaycontrol.log`: mọi user trên máy đều đọc được, và một user khác
/// có thể tạo sẵn file/symlink cùng tên trước. Log có thể chứa tên app, đường dẫn file, trạng thái quyền.
public let appLogURL: URL = {
    let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/MacHub", isDirectory: true)
    try? FileManager.default.createDirectory(
        at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
    )
    return dir.appendingPathComponent("machub.log")
}()

private let logQueue = DispatchQueue(label: "com.machub.app.log", qos: .utility)
private let maxLogBytes: UInt64 = 5 * 1024 * 1024

public func appLog(_ message: String) {
    let line = "[\(Date())] \(message)\n"
    print(line, terminator: "")
    guard let data = line.data(using: .utf8) else { return }
    logQueue.async {
        let fm = FileManager.default
        let path = appLogURL.path
        // Xoay vòng đơn giản: quá 5MB thì đổi tên thành .1 và bắt đầu file mới.
        if let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? UInt64, size > maxLogBytes {
            let old = path + ".1"
            try? fm.removeItem(atPath: old)
            try? fm.moveItem(atPath: path, toPath: old)
        }
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        if let handle = try? FileHandle(forWritingTo: appLogURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        }
    }
}
