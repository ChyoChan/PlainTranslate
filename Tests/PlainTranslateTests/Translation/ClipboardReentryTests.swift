// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import AppKit
import XCTest
@testable import PlainTranslate

@MainActor
final class ClipboardReentryTests: XCTestCase {
    func testDoubleCopyDuringSlowReadStillDeliversTheReadTimeout() async throws {
        _ = NSApplication.shared
        let started = expectation(description: "Clipboard lane blocked")
        let finished = expectation(description: "Clipboard lane drained")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        GeneralPasteboardAccess.shared.async(timeout: 5, {
            started.fulfill()
            _ = release.wait(timeout: .now() + 5)
            return true
        }, then: { _ in }, didFinish: { _ in finished.fulfill() })
        await fulfillment(of: [started], timeout: 2)

        let panel = TranslationWindowPolicy.makePanel(contentRect: NSRect(x: -10_000, y: -10_000, width: 630, height: 300))
        panel.isReleasedWhenClosed = false
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        let model = TranslationService(presentation: .compact, panel: panel)
        defer { model.close(); panel.close() }
        // All pasteboard operations expire behind the blocker; the general clipboard is never read.
        model.useCopiedText()
        let reading = model.message
        XCTAssertTrue(model.busy)
        XCTAssertNotNil(reading)
        XCTAssertNil(model.request)
        model.observeCopy(isCopy: true, isRepeat: false, time: 1, pid: 0)
        model.observeCopy(isCopy: true, isRepeat: false, time: 1.2, pid: 0)
        try await Task.sleep(nanoseconds: 1_150_000_000)
        XCTAssertFalse(model.busy, "A duplicate shortcut must not invalidate the pending read's timeout")
        XCTAssertNotEqual(model.message, reading, "The app must leave Reading copied text even when the provider never answers")
        XCTAssertNil(model.request)
        XCTAssertEqual(panel.alphaValue, 0)
        release.signal()
        await fulfillment(of: [finished], timeout: 2)
        // Drain the expired read and baseline-copy work before leaving the shared serial lane.
        let drained = expectation(description: "Expired clipboard operations drained")
        GeneralPasteboardAccess.shared.async(timeout: 2, { true }, then: { _ in drained.fulfill() })
        await fulfillment(of: [drained], timeout: 2)
    }
}
