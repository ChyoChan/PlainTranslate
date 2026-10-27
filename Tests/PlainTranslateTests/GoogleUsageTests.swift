// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Copyright (C) 2026 PlainTranslate contributors

import XCTest
@testable import PlainTranslate

final class GoogleUsageTests: XCTestCase {
    private var domain = ""
    private var defaults: UserDefaults!
    override func setUp() {
        domain = "com.chyo.plaintranslate.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: domain)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName: domain) }

    func testCountsPersistWithNoTextAndRollOverAtHongKongMidnight() {
        let store = GoogleTranslationUsageStore(defaults: defaults!)
        let before = ISO8601DateFormatter().date(from: "2026-10-31T15:59:59Z")!
        let after = before.addingTimeInterval(1)
        store.record(characterCount: "中 A\n👩🏽‍💻".unicodeScalars.count, at: before)
        let first = store.snapshot(at: before)
        XCTAssertEqual(first, .init(month: "2026-10", characters: 8, requests: 1))
        XCTAssertEqual(GoogleTranslationUsageStore(defaults: defaults!).snapshot(at: before), first)
        let saved = defaults.dictionary(forKey: DefaultsKey.translationGoogleUsage)!
        XCTAssertEqual(Set(saved.keys), ["month", "characters", "requests"])
        XCTAssertEqual(store.snapshot(at: after), .init(month: "2026-11", characters: 0, requests: 0))
        store.record(characterCount: 5, at: after)
        XCTAssertEqual(store.snapshot(at: after), .init(month: "2026-11", characters: 5, requests: 1))
    }

    func testConcurrentRecordsDoNotLoseIncrements() {
        let store = GoogleTranslationUsageStore(defaults: defaults!)
        let date = Date(timeIntervalSince1970: 1_792_000_000)
        DispatchQueue.concurrentPerform(iterations: 64) { _ in store.record(characterCount: 3, at: date) }
        XCTAssertEqual(store.snapshot(at: date).characters, 192)
        XCTAssertEqual(store.snapshot(at: date).requests, 64)
    }

    func testSynchronousDefaultsObserverCanReadSnapshotWithoutDeadlocking() {
        let store = GoogleTranslationUsageStore(defaults: defaults!)
        let token = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
            object: defaults!, queue: nil) { _ in _ = store.snapshot() }
        defer { NotificationCenter.default.removeObserver(token) }
        store.record(characterCount: 7)
        XCTAssertEqual(store.snapshot().characters, 7)
    }

    func testMalformedCountersCannotOverflowOrBecomeNegative() {
        let store = GoogleTranslationUsageStore(defaults: defaults!)
        let date = Date()
        let month = store.snapshot(at: date).month
        defaults.set(["month": month, "characters": -7, "requests": -1], forKey: DefaultsKey.translationGoogleUsage)
        XCTAssertEqual(store.snapshot(at: date).characters, 0)
        XCTAssertEqual(store.snapshot(at: date).requests, 0)
        defaults.set(["month": month, "characters": Int.max, "requests": Int.max], forKey: DefaultsKey.translationGoogleUsage)
        store.record(characterCount: 5, at: date)
        XCTAssertEqual(store.snapshot(at: date).characters, Int.max)
        XCTAssertEqual(store.snapshot(at: date).requests, Int.max)
    }

    func testReminderOnlyOncePerMonthAtExactThreshold() {
        XCTAssertEqual(GoogleTranslationUsageReminder.thresholdCharacters, 450_000)
        for count in [0, 449_999, 450_000, 500_000, Int.max] {
            let usage = GoogleTranslationUsageStore.Snapshot(month: "2026-10", characters: count, requests: 1)
            XCTAssertEqual(GoogleTranslationUsageReminder.shouldShow(usage: usage, enabled: true, lastShownMonth: nil), count >= 450_000)
            XCTAssertFalse(GoogleTranslationUsageReminder.shouldShow(usage: usage, enabled: false, lastShownMonth: nil))
            XCTAssertFalse(GoogleTranslationUsageReminder.shouldShow(usage: usage, enabled: true, lastShownMonth: "2026-10"))
        }
        XCTAssertTrue(GoogleTranslationUsageReminder.shouldShow(usage: .init(month: "2026-11", characters: 450_000, requests: 1), enabled: true, lastShownMonth: "2026-10"))
    }
}
