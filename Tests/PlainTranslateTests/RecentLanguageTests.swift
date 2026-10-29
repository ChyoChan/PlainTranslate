// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import XCTest
@testable import PlainTranslate

final class RecentLanguageTests: XCTestCase {
    func testSelectingVisibleLanguagesKeepsTabPositionsWhileUpdatingRecency() throws {
        try withDefaults { defaults in
            let sourceTabs = TranslationRecentLanguages.tabs(forSource: true, from: defaults)
            let targetTabs = TranslationRecentLanguages.tabs(forSource: false, from: defaults)
            for language in ["ja", "zh-Hant", "en"] {
                TranslationRecentLanguages.record(language, forSource: true, in: defaults)
                TranslationRecentLanguages.record(language, forSource: false, in: defaults)
                XCTAssertEqual(TranslationRecentLanguages.tabs(forSource: true, from: defaults), sourceTabs)
                XCTAssertEqual(TranslationRecentLanguages.tabs(forSource: false, from: defaults), targetTabs)
                XCTAssertEqual(TranslationRecentLanguages.load(forSource: true, from: defaults).first, language)
            }
            XCTAssertEqual(defaults.stringArray(forKey: DefaultsKey.translationSourceTabs), sourceTabs)
            XCTAssertEqual(defaults.stringArray(forKey: DefaultsKey.translationTargetTabs), targetTabs)
            TranslationRecentLanguages.record("auto", forSource: true, in: defaults)
            XCTAssertEqual(TranslationRecentLanguages.tabs(forSource: true, from: defaults), ["auto", "en", "zh-Hant"])
            TranslationRecentLanguages.record("en", forSource: true, in: defaults)
            XCTAssertEqual(TranslationRecentLanguages.tabs(forSource: true, from: defaults), ["auto", "en", "zh-Hant"])
        }
    }

    func testRecentChoicesPersistInMostRecentOrderWithoutDuplicates() throws {
        try withDefaults { defaults in
            XCTAssertEqual(TranslationRecentLanguages.load(forSource: true, from: defaults), ["en", "ja", "zh-Hant"])
            XCTAssertEqual(TranslationRecentLanguages.load(forSource: false, from: defaults), ["zh-Hant", "en", "ja"])
            TranslationRecentLanguages.record("ja", forSource: true, in: defaults)
            TranslationRecentLanguages.record("zh-Hant", forSource: true, in: defaults)
            TranslationRecentLanguages.record("zh-Hant", forSource: true, in: defaults)
            XCTAssertEqual(TranslationRecentLanguages.load(forSource: true, from: defaults), ["zh-Hant", "ja", "en"])
            XCTAssertEqual(defaults.stringArray(forKey: DefaultsKey.translationRecentSourceLanguages), ["zh-Hant", "ja", "en"])
            XCTAssertEqual(TranslationRecentLanguages.load(forSource: false, from: defaults), ["zh-Hant", "en", "ja"])
        }
    }

    func testDetectionIsOnlyASourceChoiceAndRecentListStaysAtThree() throws {
        try withDefaults { defaults in
            TranslationRecentLanguages.record("auto", forSource: true, in: defaults)
            XCTAssertEqual(TranslationRecentLanguages.load(forSource: true, from: defaults), ["auto", "en", "ja"])
            TranslationRecentLanguages.record("zh-Hant", forSource: true, in: defaults)
            XCTAssertEqual(TranslationRecentLanguages.load(forSource: true, from: defaults), ["zh-Hant", "auto", "en"])
            TranslationRecentLanguages.record("auto", forSource: false, in: defaults)
            XCTAssertEqual(TranslationRecentLanguages.load(forSource: false, from: defaults), ["zh-Hant", "en", "ja"])
        }
    }

    func testInvalidStoredChoicesAreFilteredAndMissingSlotsAreFilled() throws {
        try withDefaults { defaults in
            defaults.set(["removed-language", "ja", "ja", "auto", "en", "zh-Hant"], forKey: DefaultsKey.translationRecentSourceLanguages)
            XCTAssertEqual(TranslationRecentLanguages.load(forSource: true, from: defaults), ["ja", "auto", "en"])
            defaults.set(["auto", "unknown", "en", "en"], forKey: DefaultsKey.translationRecentTargetLanguages)
            XCTAssertEqual(TranslationRecentLanguages.load(forSource: false, from: defaults), ["en", "zh-Hant", "ja"])
            defaults.set("not-an-array", forKey: DefaultsKey.translationRecentSourceLanguages)
            XCTAssertEqual(TranslationRecentLanguages.load(forSource: true, from: defaults), ["en", "ja", "zh-Hant"])
        }
    }

    private func withDefaults(_ check: (UserDefaults) throws -> Void) throws {
        let domain = "PlainTranslate-recent-language-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        try check(defaults)
    }
}
