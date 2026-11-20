// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import XCTest
@testable import AgentKit

final class ClaudeCredentialsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testParsesTokenAndExpiryInMilliseconds() throws {
        let data = Data(#"{"claudeAiOauth":{"accessToken":"tok","refreshToken":"r","expiresAt":1800003600000}}"#.utf8)
        let c = try XCTUnwrap(ClaudeCredentials.parse(data))
        XCTAssertEqual(c.accessToken, "tok")
        XCTAssertEqual(c.expiresAt, Date(timeIntervalSince1970: 1_800_003_600))
        XCTAssertTrue(c.isValid(at: now))
    }

    func testExpiredOrAboutToExpireIsInvalid() {
        let c = ClaudeCredentials(accessToken: "t", expiresAt: now.addingTimeInterval(30))
        XCTAssertFalse(c.isValid(at: now), "Còn < 60s coi như hết hạn để không gửi token sắp chết")
        XCTAssertFalse(ClaudeCredentials(accessToken: "t", expiresAt: now.addingTimeInterval(-5)).isValid(at: now))
        XCTAssertTrue(ClaudeCredentials(accessToken: "t", expiresAt: now.addingTimeInterval(600)).isValid(at: now))
    }

    func testMissingExpiryIsTreatedAsValid() throws {
        let c = try XCTUnwrap(ClaudeCredentials.parse(Data(#"{"claudeAiOauth":{"accessToken":"tok"}}"#.utf8)))
        XCTAssertNil(c.expiresAt)
        XCTAssertTrue(c.isValid(at: now))
    }

    func testRejectsMalformedOrEmpty() {
        XCTAssertNil(ClaudeCredentials.parse(Data("not json".utf8)))
        XCTAssertNil(ClaudeCredentials.parse(Data(#"{"other":1}"#.utf8)))
        XCTAssertNil(ClaudeCredentials.parse(Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8)))
    }
}
