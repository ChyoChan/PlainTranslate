// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ChyoChan

import AppKit
import XCTest
@testable import PlainTranslate

final class WindowPresentationTests: XCTestCase {
    @MainActor
    func testSwitchingModesKeepsTheHostAndRestoresWindowBehavior() {
        _ = NSApplication.shared
        let panel = TranslationPanel(contentRect: NSRect(x: 0, y: 0, width: 630, height: 300),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        let host = NSView(frame: panel.contentView!.bounds)
        panel.contentView = host
        defer { panel.close() }

        for mode in [TranslationPresentation.compact, .editor, .compact, .editor] {
            TranslationWindowPolicy.configure(panel, for: mode)
            XCTAssertEqual(panel.level, mode == .compact ? .floating : .normal)
            XCTAssertEqual(panel.isFloatingPanel, mode == .compact)
            XCTAssertEqual(panel.canBecomeMain, mode == .editor)
            XCTAssertTrue(panel.canBecomeKey)
            XCTAssertFalse(panel.hidesOnDeactivate)
            XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
            XCTAssertTrue(panel.contentView === host, "Changing mode must not replace the translation host")
            XCTAssertFalse(panel.isVisible, "This test must never show a real window")
        }
    }
}
