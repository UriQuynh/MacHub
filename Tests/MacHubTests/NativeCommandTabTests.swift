// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

import XCTest
import CoreGraphics
@testable import MacHub

/// Chỉ kiểm thử chính sách (thuần hàm). Không bật/tắt ⌘Tab thật của máy chạy test.
@MainActor
final class NativeCommandTabTests: XCTestCase {
    private func config(_ bindings: [ShortcutBinding]) -> ShortcutConfiguration {
        var c = ShortcutConfiguration()
        c.bindings[.switchWindows] = bindings
        return c
    }

    func testDefaultBindingsIncludeCommandTabSoNativeIsOverridden() {
        XCTAssertTrue(NativeCommandTab.shouldOverride(configuration: ShortcutConfiguration(), altTabEnabled: true, tapActive: true))
    }

    func testOptionTabOnlyLeavesNativeCommandTabAlone() {
        let c = config([ShortcutBinding(48, .maskAlternate)])
        XCTAssertFalse(NativeCommandTab.shouldOverride(configuration: c, altTabEnabled: true, tapActive: true))
    }

    func testCustomBindingWithCommandTabOverridesEvenWhenOptionTabRemoved() {
        let c = config([ShortcutBinding(48, .maskCommand)])
        XCTAssertTrue(NativeCommandTab.shouldOverride(configuration: c, altTabEnabled: true, tapActive: true))
    }

    func testNeverOverrideWhenAltTabDisabledOrTapNotActive() {
        let c = ShortcutConfiguration()
        XCTAssertFalse(NativeCommandTab.shouldOverride(configuration: c, altTabEnabled: false, tapActive: true))
        XCTAssertFalse(NativeCommandTab.shouldOverride(configuration: c, altTabEnabled: true, tapActive: false))
    }

    func testOtherKeysOrExtraModifiersDoNotCountAsCommandTab() {
        // ⌘` , ⌘⌥Tab, ⌃Tab không phải ⌘Tab.
        for binding in [ShortcutBinding(50, .maskCommand),
                        ShortcutBinding(48, [.maskCommand, .maskAlternate]),
                        ShortcutBinding(48, .maskControl)] {
            XCTAssertFalse(NativeCommandTab.shouldOverride(configuration: config([binding]), altTabEnabled: true, tapActive: true), "\(binding)")
        }
        XCTAssertFalse(NativeCommandTab.shouldOverride(configuration: config([]), altTabEnabled: true, tapActive: true))
    }

    func testSystemAPIIsAvailableAndReadOnlyProbeWorks() {
        XCTAssertNotNil(NativeCommandTab.nativeIsEnabled, "CGSIsSymbolicHotKeyEnabled phải có trên macOS này")
        XCTAssertEqual(NativeCommandTab.hotKeys, [1, 2])
    }
}
