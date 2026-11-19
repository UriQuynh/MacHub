// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import XCTest
@testable import MacHub

final class SecureStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        SecureStore.service = "com.machub.app.tests.\(UUID().uuidString)"
        SecureStore.resetKeyForTesting()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("machub-securestore-\(UUID().uuidString)", isDirectory: true)
        SecureStore.ensurePrivateDirectory(dir)
    }

    override func tearDownWithError() throws {
        SecureStore.resetKeyForTesting()
        try? FileManager.default.removeItem(at: dir)
    }

    func testRoundTripEncryptsAndRestores() throws {
        let url = dir.appendingPathComponent("clip.json")
        let secret = Data("mật khẩu-ví-dụ-123 SECRET_MARKER".utf8)

        try SecureStore.write(secret, to: url)

        let raw = try Data(contentsOf: url)
        XCTAssertTrue(raw.starts(with: Data("MHE1".utf8)), "File phải có header MHE1")
        XCTAssertNil(raw.range(of: Data("SECRET_MARKER".utf8)), "Bản rõ không được nằm trên đĩa")
        XCTAssertTrue(SecureStore.isEncrypted(url))
        XCTAssertEqual(try SecureStore.read(from: url), secret)
    }

    func testFileAndDirectoryPermissions() throws {
        let url = dir.appendingPathComponent("perm.json")
        try SecureStore.write(Data("x".utf8), to: url)
        let fileMode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        let dirMode = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int
        XCTAssertEqual(fileMode, 0o600)
        XCTAssertEqual(dirMode, 0o700)
    }

    func testLegacyPlaintextIsReadAsIs() throws {
        let url = dir.appendingPathComponent("legacy.json")
        let legacy = Data(#"[{"text":"cũ"}]"#.utf8)
        try legacy.write(to: url)

        XCTAssertFalse(SecureStore.isEncrypted(url))
        XCTAssertEqual(try SecureStore.read(from: url), legacy)
    }

    func testTamperedCiphertextIsRejected() throws {
        let url = dir.appendingPathComponent("tamper.json")
        try SecureStore.write(Data("không được sửa".utf8), to: url)
        var raw = try Data(contentsOf: url)
        raw[raw.count - 1] ^= 0xFF
        try raw.write(to: url)

        XCTAssertThrowsError(try SecureStore.read(from: url))
    }

    func testKeyPersistsAcrossCacheReset() throws {
        let url = dir.appendingPathComponent("persist.json")
        try SecureStore.write(Data("giữ khóa".utf8), to: url)

        // Mô phỏng khởi động lại app: bỏ cache trong RAM, khóa phải đọc lại được từ Keychain.
        SecureStore.clearCachedKeyForTesting()

        XCTAssertEqual(try SecureStore.read(from: url), Data("giữ khóa".utf8))
    }
}

final class AppConfigTests: XCTestCase {
    func testUpdatesDisabledOutsideAppBundle() {
        // Test chạy từ xctest, không phải MacHub.app → không được khởi động Sparkle.
        XCTAssertTrue(UpdateManager.updatesDisabled)
    }

    func testLogFileLivesInUserLibrary() {
        XCTAssertTrue(appLogURL.path.hasSuffix("/Library/Logs/MacHub/machub.log"))
        XCTAssertFalse(appLogURL.path.hasPrefix("/tmp"))
    }
}
