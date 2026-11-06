// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import NaturalLanguage
import XCTest
@testable import PlainTranslate

final class LanguageDetectionTests: XCTestCase {
    func testConfidencePolicyPreservesClearLanguagesAndOnlyDefaultsShortASCIIToEnglish() {
        let fixtures: [(String, [NLLanguage: Double], String?)] = [
            ("word", [.dutch: 0.46, .english: 0.28], "en"),
            ("CPU", [.portuguese: 0.22, .danish: 0.17], "en"),
            ("a", [:], "en"), ("128GB", [:], "en"), ("C++", [:], "en"),
            ("bonjour", [.french: 0.99], "fr"),
            ("Bonjour, comment allez-vous aujourd’hui ?", [.french: 0.99], "fr"),
            ("こんにちは", [.japanese: 0.99], "ja"),
            ("家庭", [.traditionalChinese: 0.45, .simplifiedChinese: 0.44, .japanese: 0.11], "zh-Hant"),
            ("家庭", [.simplifiedChinese: 0.6, .traditionalChinese: 0.3, .japanese: 0.1], "zh-Hans"),
            ("銀行", [.japanese: 0.57, .traditionalChinese: 0.43], nil),
            ("Hello 世界", [.english: 0.5, .traditionalChinese: 0.5], nil),
            ("한국어", [.korean: 0.99], "ko"),
            ("résumé", [.french: 0.6], nil),
            ("12345", [.english: 1], nil), ("...", [:], nil), ("🙂", [:], nil),
            (" \n\t ", [:], nil),
            (String(repeating: "a", count: 40), [:], "en"),
            (String(repeating: "a", count: 41), [.english: 0.5], nil),
            ("a b c d", [.english: 0.5], nil),
            ("  word\n", [.dutch: 0.46, .english: 0.28], "en"),
        ]
        for (text, hypotheses, expected) in fixtures {
            XCTAssertEqual(TranslationLanguageDetection.source(for: text, hypotheses: hypotheses), expected,
                           "Unexpected policy for \(text)")
        }
    }

    func testNativeRecognizerAndReadAloudShareShortWordDetection() {
        for word in ["family", "word", "MapReduce", "CPU", "GDP", "I", "cat"] {
            XCTAssertEqual(TranslationLanguageDetection.source(for: word), "en", word)
            XCTAssertEqual(TranslationSpeechLanguage.preferred(for: word, language: "auto", chineseVoice: "yue-HK"),
                           "en-US", word)
        }
        XCTAssertEqual(TranslationLanguageDetection.source(for: "こんにちは"), "ja")
        XCTAssertEqual(TranslationLanguageDetection.source(for: "這是一段繁體中文的測試文字。"), "zh-Hant")
        XCTAssertNil(TranslationLanguageDetection.source(for: "12345"))
    }

    @MainActor
    func testShortEnglishAutoInputGetsAnExplicitAppleSourceBeforeItsSessionStarts() throws {
        try withFixture { model in
            model.source = "auto"
            for word in ["family", "word", "MapReduce", "CPU"] {
                model.input = word
                model.inputDidChange()
                model.translate()
                let request = try XCTUnwrap(model.request)
                XCTAssertEqual(request.source, "en", "Resolve short English before invoking Apple's detection UI: \(word)")
                XCTAssertEqual(request.text, word)
                XCTAssertEqual(model.source, "auto", "Keep the user's automatic source selection")
                model.cancel()
            }
        }
    }

    @MainActor
    func testManualSourcesAndGoogleAutomaticDetectionStayUnchanged() throws {
        try withFixture { model in
            model.source = "ja"
            model.input = "word"
            model.translate()
            XCTAssertEqual(try XCTUnwrap(model.request).source, "ja")
        }
        try withFixture(engine: .google) { model in
            model.source = "auto"
            model.input = "word"
            model.translate()
            let request = try XCTUnwrap(model.request)
            XCTAssertNil(request.source, "Google must retain its own automatic language detection")
            XCTAssertEqual(request.engine, .google)
            XCTAssertEqual(request.text, "word")
        }
    }

    @MainActor
    func testAmbiguousNonLetterInputStillLeavesDetectionToApple() throws {
        try withFixture { model in
            model.source = "auto"
            model.input = "12345"
            model.translate()
            XCTAssertNil(try XCTUnwrap(model.request).source)
        }
    }

    @MainActor
    func testDetectedSourceIsUsedInCacheWithoutChangingOriginalTextOrPreferences() throws {
        try withFixture { model in
            model.source = "auto"
            model.input = "  word\n"
            model.translate()
            let first = try XCTUnwrap(model.request)
            XCTAssertEqual(first.source, "en")
            XCTAssertEqual(first.text, "  word\n")
            model.finish(first.id, result: .success("字詞"))
            model.inputDidChange()
            model.source = "en"
            model.translate()
            XCTAssertNil(model.request, "The resolved and explicit language must share the same cache key")
            XCTAssertEqual(model.output, "字詞")
            XCTAssertEqual(model.input, "  word\n")
            XCTAssertEqual(model.cachedTranslationCount, 1)
        }
    }

    @MainActor
    func testSameLanguageInferenceRetainsAppleFlowInsteadOfSilentlySkippingText() throws {
        try withFixture { model in
            model.source = "auto"
            model.target = "en"
            model.input = "  word\n"
            model.translate()
            let request = try XCTUnwrap(model.request)
            XCTAssertNil(request.source)
            XCTAssertEqual(request.text, "  word\n")
            XCTAssertTrue(model.busy)
            XCTAssertTrue(model.output.isEmpty, "Do not claim an ambiguous input is already translated")
            XCTAssertEqual(model.source, "auto")
            XCTAssertEqual(model.cachedTranslationCount, 0)
        }
    }

    @MainActor
    private func withFixture(engine: TranslationEngine = .apple, _ check: (TranslationService) throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let previous = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        let keys = [DefaultsKey.translationRecentSourceLanguages, DefaultsKey.translationRecentTargetLanguages,
                    DefaultsKey.translationSourceTabs, DefaultsKey.translationTargetTabs]
        let saved = keys.map { defaults.object(forKey: $0) }
        var fixture = previous
        fixture[DefaultsKey.translationEngine] = engine.rawValue
        fixture[DefaultsKey.translationPDFLineBreakCleanup] = false
        fixture[DefaultsKey.translationRecentSourceLanguages] = ["en", "ja", "zh-Hant"]
        fixture[DefaultsKey.translationRecentTargetLanguages] = ["zh-Hant", "en", "ja"]
        defaults.setVolatileDomain(fixture, forName: UserDefaults.argumentDomain)
        let model = TranslationService(googleTranslation: { _ in throw GoogleTranslationError.network })
        defer {
            model.close()
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
            defaults.setVolatileDomain(previous, forName: UserDefaults.argumentDomain)
        }
        try check(model)
    }
}
