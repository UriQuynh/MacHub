// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import XCTest
import AppKit
@testable import MacHub

final class AltTabSpacesTests: XCTestCase {
    private let a = "AAAAAAAA-0000-0000-0000-000000000001"
    private let b = "BBBBBBBB-0000-0000-0000-000000000002"

    private func displays(mainAsLiteral: Bool = false) -> [[String: Any]] {
        [
            ["Display Identifier": mainAsLiteral ? "Main" : a,
             "Spaces": [["id64": 1], ["id64": 2], ["id64": 3]]],
            ["Display Identifier": b, "Spaces": [["id64": 10], ["id64": 11]]],
        ]
    }

    func testNoFilterReturnsEverySpace() {
        XCTAssertEqual(spaceIDs(in: displays(), onlyDisplay: nil, primaryUUID: a), [1, 2, 3, 10, 11])
    }

    /// Màn hình đang dùng chỉ lấy các Space của chính nó (gồm Space full-screen), bỏ Space của màn hình kia.
    func testFilterKeepsAllSpacesOfThatDisplayOnly() {
        XCTAssertEqual(spaceIDs(in: displays(), onlyDisplay: a, primaryUUID: a), [1, 2, 3])
        XCTAssertEqual(spaceIDs(in: displays(), onlyDisplay: b, primaryUUID: a), [10, 11])
    }

    func testMainDisplayReportedAsLiteralMainIsMatchedByPrimaryUUID() {
        XCTAssertEqual(spaceIDs(in: displays(mainAsLiteral: true), onlyDisplay: a, primaryUUID: a), [1, 2, 3])
        // Màn hình phụ không bị nhầm là "Main".
        XCTAssertEqual(spaceIDs(in: displays(mainAsLiteral: true), onlyDisplay: b, primaryUUID: a), [10, 11])
    }

    /// Không nhận ra màn hình thì hiện tất cả, không để Alt-Tab trống vì lỗi nhận dạng.
    func testUnknownDisplayFallsBackToEverySpace() {
        XCTAssertEqual(spaceIDs(in: displays(), onlyDisplay: "UNKNOWN", primaryUUID: a), [1, 2, 3, 10, 11])
        XCTAssertEqual(spaceIDs(in: [], onlyDisplay: a, primaryUUID: a), [])
    }

    func testBuiltInScreenHasUUIDString() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let uuid = try XCTUnwrap(displayUUIDString(for: screen))
        XCTAssertEqual(uuid.count, 36)
    }
}
