// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ChyoChan

import AppKit
import XCTest
@testable import PlainTranslate

final class WindowPresentationTests: XCTestCase {
    @MainActor
    func testPinningPreservesInFlightTextAndResetsOnClose() throws {
        let model = TranslationService(presentation: .compact)
        defer { model.close() }
        model.input = "Keep this original while reading another app."
        model.translate()
        let request = try XCTUnwrap(model.request)
        XCTAssertFalse(model.isPinned)
        model.togglePin()
        XCTAssertTrue(model.isPinned)
        XCTAssertEqual(model.request?.id, request.id, "Pinning must not restart translation")
        XCTAssertEqual(model.input, "Keep this original while reading another app.")
        model.finish(request.id, result: .success("在其他 App 閱讀時保留原文。"))
        model.togglePin()
        XCTAssertFalse(model.isPinned)
        XCTAssertFalse(TranslationDismissalPolicy.shouldDismiss(presentation: .compact, isVisible: true,
            isPinned: model.isPinned, clickIsInside: true, menuIsTracking: false,
            hasModal: false, isAssistiveKeyboard: false), "Unpinning inside the popup must not close it")
        XCTAssertTrue(TranslationDismissalPolicy.shouldDismiss(presentation: .compact, isVisible: true,
            isPinned: model.isPinned, clickIsInside: false, menuIsTracking: false,
            hasModal: false, isAssistiveKeyboard: false))
        XCTAssertFalse(model.output.isEmpty)
        model.togglePin()
        model.close()
        XCTAssertFalse(model.isPinned)
        XCTAssertTrue(model.input.isEmpty)
        XCTAssertTrue(model.output.isEmpty)
    }

    @MainActor
    func testEditorDoesNotAcquirePopupPinning() {
        let model = TranslationService(presentation: .editor)
        defer { model.close() }
        model.togglePin()
        XCTAssertFalse(model.isPinned)
    }

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
