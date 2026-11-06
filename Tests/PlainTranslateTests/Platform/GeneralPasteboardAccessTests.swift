// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import AppKit
import XCTest
@testable import PlainTranslate

@MainActor
final class GeneralPasteboardAccessTests: XCTestCase {
    func testTranslationReadsOnlyFreshUnprotectedClipboardText() throws {
        let board = NSPasteboard(name: .init("test.plaintranslate.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        let baseline = board.changeCount
        XCTAssertThrowsError(try GeneralPasteboardAccess.translationText(from: board,
            requiringChangeAfter: baseline, requiresFreshCopy: true))
        board.clearContents()
        XCTAssertTrue(board.setString(" whole selection\n", forType: .string))
        XCTAssertEqual(try GeneralPasteboardAccess.translationText(from: board,
            requiringChangeAfter: baseline, requiresFreshCopy: true), " whole selection\n")
        for type in TranslationTextPlan.protectedTypes {
            board.clearContents()
            XCTAssertTrue(board.setString("fixture_private", forType: .string))
            XCTAssertTrue(board.setData(Data(), forType: .init(type)))
            XCTAssertThrowsError(try GeneralPasteboardAccess.translationText(from: board)) { error in
                guard case TranslationInputError.sensitive = error else { return XCTFail("Expected protected content rejection") }
            }
        }
    }

    func testClipboardReplacementDuringPromisedTextReadIsRejected() {
        let board = NSPasteboard(name: .init("test.plaintranslate.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        let provider = ReplacingPasteboardProvider()
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setDataProvider(provider, forTypes: [.string]))
        XCTAssertTrue(board.writeObjects([item]))
        XCTAssertThrowsError(try GeneralPasteboardAccess.translationText(from: board)) { error in
            guard case TranslationInputError.clipboardChanged = error else { return XCTFail("Expected changed clipboard rejection") }
        }
        XCTAssertTrue(provider.wasCalled)
    }

    func testSuccessfulWorkRunsOffMainAndDeliversOnMain() async {
        let completed = expectation(description: "Result delivered")
        let finished = expectation(description: "Work finished")
        var deliveries = 0
        GeneralPasteboardAccess.shared.async(timeout: 5, {
            XCTAssertFalse(Thread.isMainThread)
            return 42
        }, then: { value in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(value, 42)
            deliveries += 1
            completed.fulfill()
        }, didFinish: { value in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(value, 42)
            finished.fulfill()
        })
        await fulfillment(of: [completed, finished], timeout: 2)
        XCTAssertEqual(deliveries, 1)
    }

    func testTimeoutRejectsLateResultButStillReportsActualFinish() async {
        let started = expectation(description: "Work started")
        let timedOut = expectation(description: "Deadline delivered nil")
        let finished = expectation(description: "Late work finished")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        var deliveries = 0
        GeneralPasteboardAccess.shared.async(timeout: 1, {
            started.fulfill()
            XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            return 7
        }, then: { value in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertNil(value)
            deliveries += 1
            timedOut.fulfill()
            release.signal()
        }, didFinish: { value in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(value, 7)
            finished.fulfill()
        })
        await fulfillment(of: [started, timedOut, finished], timeout: 3)
        XCTAssertEqual(deliveries, 1, "Late completion must not deliver again")
    }

    func testExpiredQueuedWorkNeverStartsAndFinishesAfterTheSerialBlocker() async {
        let started = expectation(description: "Serial blocker started")
        let blockerFinished = expectation(description: "Serial blocker finished")
        let timedOut = expectation(description: "Queued operation timed out")
        let expiredFinished = expectation(description: "Expired operation skipped")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        var blockerDidFinish = false
        var deliveries = 0
        GeneralPasteboardAccess.shared.async(timeout: 5, {
            started.fulfill()
            XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            return 1
        }, then: { value in
            XCTAssertEqual(value, 1)
        }, didFinish: { _ in
            blockerDidFinish = true
            blockerFinished.fulfill()
        })
        await fulfillment(of: [started], timeout: 2)
        GeneralPasteboardAccess.shared.async(timeout: 0, { () -> Int? in
            XCTFail("Expired queued work must not run")
            return 2
        }, then: { value in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertFalse(blockerDidFinish, "Queued work must not bypass the serial blocker")
            XCTAssertNil(value)
            deliveries += 1
            timedOut.fulfill()
            release.signal()
        }, didFinish: { value in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(blockerDidFinish)
            XCTAssertNil(value)
            expiredFinished.fulfill()
        })
        await fulfillment(of: [timedOut, blockerFinished, expiredFinished], timeout: 2)
        XCTAssertEqual(deliveries, 1)
    }
}

private final class ReplacingPasteboardProvider: NSObject, NSPasteboardItemDataProvider {
    var wasCalled = false

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {
        wasCalled = true
        item.setString("fixture_public", forType: type)
        pasteboard?.clearContents()
        pasteboard?.setString("fixture_private", forType: .string)
        pasteboard?.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
    }
}
