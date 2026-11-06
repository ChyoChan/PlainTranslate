// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ChyoChan

import AppKit
import XCTest
@testable import PlainTranslate

final class WindowPresentationTests: XCTestCase {
    @MainActor
    func testEditorUsesAnActivatingWindowThatParticipatesInMissionControl() {
        _ = NSApplication.shared
        let panel = TranslationWindowPolicy.makePanel(contentRect: NSRect(x: 0, y: 0, width: 880, height: 520))
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        for mode in [TranslationPresentation.editor, .compact, .editor] {
            TranslationWindowPolicy.configure(panel, for: mode)
            if mode == .editor {
                XCTAssertFalse(panel.styleMask.contains(.nonactivatingPanel),
                               "The full editor must allow its owning app to activate when selected")
                XCTAssertTrue(panel.collectionBehavior.contains(.managed),
                              "The editor must participate explicitly in Mission Control and Spaces")
                XCTAssertFalse(panel.collectionBehavior.contains(.transient))
                XCTAssertFalse(panel.collectionBehavior.contains(.moveToActiveSpace))
                XCTAssertFalse(panel.collectionBehavior.contains(.fullScreenAuxiliary))
                XCTAssertTrue(panel.canBecomeMain)
                XCTAssertTrue(panel.canBecomeKey)
            }
            XCTAssertFalse(panel.isVisible, "The configuration fixture must not present a window")
        }
    }

    @MainActor
    func testShowingCompactResultDoesNotChangeApplicationOrKeyboardFocus() {
        _ = NSApplication.shared
        let panel = TranslationWindowPolicy.makePanel(contentRect: NSRect(x: -10_000, y: -10_000, width: 630, height: 300))
        panel.isReleasedWhenClosed = false
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        defer { panel.close() }
        TranslationWindowPolicy.configure(panel, for: .compact)
        let activeBefore = NSApp.isActive
        let keyBefore = NSApp.keyWindow
        let mainBefore = NSApp.mainWindow
        TranslationWindowPolicy.present(panel, for: .compact)
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertFalse(panel.isMainWindow)
        XCTAssertEqual(NSApp.isActive, activeBefore)
        XCTAssertTrue(NSApp.keyWindow === keyBefore)
        XCTAssertTrue(NSApp.mainWindow === mainBefore)
    }

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
        let panel = TranslationWindowPolicy.makePanel(contentRect: NSRect(x: 0, y: 0, width: 630, height: 300))
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
            XCTAssertEqual(panel.collectionBehavior.contains(.transient), mode == .compact)
            XCTAssertEqual(panel.collectionBehavior.contains(.managed), mode == .editor)
            XCTAssertFalse(panel.styleMask.contains(.nonactivatingPanel))
            XCTAssertTrue(panel.contentView === host, "Changing mode must not replace the translation host")
            XCTAssertFalse(panel.isVisible, "This test must never show a real window")
        }
    }
}
