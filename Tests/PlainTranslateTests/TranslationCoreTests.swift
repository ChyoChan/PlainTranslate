// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Copyright (C) 2026 PlainTranslate contributors
// Adapted from the Vorssaint translation regression fixtures.

import XCTest
@testable import PlainTranslate

final class TranslationCoreTests: XCTestCase {
    func testStandaloneIdentityAndSafeDefaultRegistration() {
        let domain = "com.chyo.plaintranslate.tests.preferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        AppPreferences.registerDefaults(in: defaults)
        XCTAssertEqual(AppPreferences.bundleIdentifier, "com.chyo.plaintranslate")
        XCTAssertFalse(defaults.bool(forKey: DefaultsKey.translationDoubleCopyEnabled))
        XCTAssertEqual(defaults.string(forKey: DefaultsKey.translationEngine), "apple")
        XCTAssertTrue(defaults.bool(forKey: DefaultsKey.translationPDFLineBreakCleanup))
        XCTAssertEqual(defaults.double(forKey: DefaultsKey.translationPopupWidth), 630)
        XCTAssertTrue(TranslationKeychain().service.hasSuffix(".translation.google"))
        XCTAssertFalse(TranslationKeychain().service.lowercased().contains("vorssaint"))
        defaults.set("google", forKey: DefaultsKey.translationEngine)
        AppPreferences.registerDefaults(in: defaults)
        XCTAssertEqual(defaults.string(forKey: DefaultsKey.translationEngine), "google")
    }

    func testLanguageAndEngineDefaults() {
        XCTAssertEqual(TranslationLanguageDefaults.source, "en")
        XCTAssertEqual(TranslationLanguageDefaults.target, "zh-Hant")
        XCTAssertEqual(TranslationRequest(text: "Hello", source: nil, target: "zh-Hant").engine, .apple)
        XCTAssertEqual(Set(TranslationLanguageDefaults.languages), ["en", "zh-Hant", "ja"])
    }

    func testDoubleCopyRequiresFreshPairInSameApplication() {
        var detector = TranslationDoubleCopyDetector()
        XCTAssertFalse(detector.observe(isCopy: true, isRepeat: false, time: 1, pid: 1))
        XCTAssertTrue(detector.observe(isCopy: true, isRepeat: false, time: 1.3, pid: 1))
        XCTAssertFalse(detector.observe(isCopy: true, isRepeat: false, time: 1.4, pid: 1))
        XCTAssertFalse(detector.observe(isCopy: true, isRepeat: false, time: 3, pid: 1))
        XCTAssertFalse(detector.observe(isCopy: true, isRepeat: true, time: 3.1, pid: 1))
        XCTAssertFalse(detector.observe(isCopy: false, isRepeat: false, time: 3.2, pid: 1))
        XCTAssertFalse(detector.observe(isCopy: true, isRepeat: false, time: 3.3, pid: 1))
        XCTAssertFalse(detector.observe(isCopy: true, isRepeat: false, time: 3.4, pid: 2))
        XCTAssertFalse(detector.observe(isCopy: true, isRepeat: false, time: 4.2, pid: 2))
        XCTAssertTrue(detector.observe(isCopy: true, isRepeat: false, time: 4.8, pid: 2))
        XCTAssertFalse(TranslationTextPlan.isFreshCopy(baseline: nil, current: 9))
        XCTAssertFalse(TranslationTextPlan.isFreshCopy(baseline: 9, current: 9))
        XCTAssertTrue(TranslationTextPlan.isFreshCopy(baseline: 9, current: 10))
    }

    func testSensitiveEmptyAndOversizedSelectionsFailClosed() throws {
        for text in ["", " ", "\n\t\r\n"] { XCTAssertThrowsError(try TranslationTextPlan.validate(text)) }
        for type in TranslationTextPlan.protectedTypes {
            XCTAssertThrowsError(try TranslationTextPlan.validate("private", types: [type])) { error in
                guard case TranslationInputError.sensitive = error else { return XCTFail("Expected sensitive clipboard rejection") }
            }
        }
        XCTAssertEqual(try TranslationTextPlan.validate(String(repeating: "字", count: 40_000)).count, 40_000)
        XCTAssertThrowsError(try TranslationTextPlan.validate(String(repeating: "字", count: 40_001)))
    }

    func testGenerationInvalidatesOldReadsAndResults() {
        var generation = TranslationGeneration()
        let first = generation.current
        let next = generation.advance()
        XCTAssertFalse(generation.accepts(first))
        XCTAssertTrue(generation.accepts(next))
        generation.advance()
        XCTAssertFalse(generation.accepts(next))
        XCTAssertNotEqual(TranslationRequest(text: "same", source: nil, target: "ja").id,
                          TranslationRequest(text: "same", source: nil, target: "ja").id)
    }

    func testWholeSelectionIsPassedOnceWithoutTrimmingOrSplitting() async throws {
        for original in [" First line.\n\nSecond line. \n", "中文第一段。\r\n第二段。",
                         "\t leading\tand trailing \t", String(repeating: "👩🏽‍💻中é", count: 1_800)] {
            var inputs: [String] = []
            let result = try await TranslationTextPlan.translate(original) { text in
                inputs.append(text)
                return "complete engine result"
            }
            XCTAssertEqual(inputs, [original])
            XCTAssertEqual(result, "complete engine result")
        }
    }

    func testCancellationRejectsEngineResult() async {
        let task = Task {
            try await TranslationTextPlan.translate("private source") { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return "stale output"
            }
        }
        do { _ = try await task.value; XCTFail("Cancelled output must not be returned") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testOutsideClickPolicyPreservesMenusModalPanelsAndEditor() {
        for mode in [TranslationPresentation.compact, .editor] {
            for mask in 0..<32 {
                let visible = mask & 1 != 0, inside = mask & 2 != 0
                let menu = mask & 4 != 0, modal = mask & 8 != 0, keyboard = mask & 16 != 0
                XCTAssertEqual(TranslationDismissalPolicy.shouldDismiss(presentation: mode, isVisible: visible,
                    clickIsInside: inside, menuIsTracking: menu, hasModal: modal, isAssistiveKeyboard: keyboard),
                    mode == .compact && visible && !inside && !menu && !modal && !keyboard)
            }
        }
    }

    func testPopupDimensionsClampCorruptPreferences() {
        for invalid in [Double.nan, .infinity, -.infinity, 0, -1] {
            XCTAssertEqual(TranslationCompactLayout.width(invalid), 630)
            XCTAssertEqual(TranslationCompactLayout.fontSize(invalid), 20)
        }
        XCTAssertEqual(TranslationCompactLayout.width(50), 400)
        XCTAssertEqual(TranslationCompactLayout.width(50_000), 1_200)
        XCTAssertEqual(TranslationCompactLayout.fontSize(1), 12)
        XCTAssertEqual(TranslationCompactLayout.fontSize(200), 32)
        XCTAssertEqual(TranslationCompactLayout.height(for: 120, available: 900), 210)
        XCTAssertEqual(TranslationCompactLayout.height(for: 420.2, available: 900), 421)
        XCTAssertEqual(TranslationCompactLayout.height(for: 20_000, available: 900), 720)
        XCTAssertEqual(TranslationCompactLayout.height(for: 720, available: 500), 500)
    }

    func testPDFCleanupPreservesIntentionalStructureAndIsIdempotent() {
        let fixtures: [(String, String)] = [
            ("", ""), ("One line stays unchanged.", "One line stays unchanged."),
            ("Several wrapped\nlines form one\ncomplete sentence.", "Several wrapped lines form one complete sentence."),
            ("First paragraph wraps\nhere.\n\nSecond paragraph wraps\nhere.", "First paragraph wraps here.\n\nSecond paragraph wraps here."),
            ("First paragraph.\nSecond paragraph.", "First paragraph.\nSecond paragraph."),
            ("Heading:\nBody text wraps\nhere", "Heading:\nBody text wraps here"),
            ("Intro\n• First item\n• Second item", "Intro\n• First item\n• Second item"),
            ("Intro\n\u{F0A7} First item\n\u{F0A7} Second item", "Intro\n\u{F0A7} First item\n\u{F0A7} Second item"),
            ("- First item\n  continued item\n- Second item", "- First item\n  continued item\n- Second item"),
            ("1. First\n2. Second\n3) Third", "1. First\n2. Second\n3) Third"),
            ("（一）第一項\n（二）第二項\n三、第三項\n4、第四項", "（一）第一項\n（二）第二項\n三、第三項\n4、第四項"),
            ("if condition {\n    call()\n}", "if condition {\n    call()\n}"),
            ("Name\tValue\nOne\t1", "Name\tValue\nOne\t1"),
            ("Name  Value\nOne   1", "Name  Value\nOne   1"),
            ("這是一段由 PDF 複製的\n中文內容。", "這是一段由 PDF 複製的中文內容。"),
            ("日本語の\n文章です。", "日本語の文章です。"),
            ("한국어\n문장", "한국어 문장"),
            ("Hello 👩🏽‍💻\nworld", "Hello 👩🏽‍💻 world"),
            ("A multi-\ntenant model", "A multi-tenant model"),
            ("First\r\nsecond\r\n\r\nThird\r\nfourth", "First second\n\nThird fourth"),
            ("First\rsecond", "First second"), ("First\n\n\nSecond", "First\n\n\nSecond"),
            (" Leading line \nnext line", " Leading line \nnext line"), ("\n\t\n", "\n\t\n"),
        ]
        for (original, expected) in fixtures {
            let prepared = TranslationLineBreakCleanup.prepare(original, enabled: true)
            XCTAssertEqual(prepared, expected)
            XCTAssertEqual(TranslationLineBreakCleanup.prepare(original, enabled: false), original)
            XCTAssertEqual(TranslationLineBreakCleanup.prepare(prepared, enabled: true), prepared)
        }
    }

    func testVoicePreferencesNeverMixCantoneseAndMandarin() {
        XCTAssertEqual(TranslationSpeechLanguage.defaultChineseVoice, "yue-HK")
        XCTAssertEqual(TranslationSpeechLanguage.voiceGroup("zh-HK"), "yue-HK")
        XCTAssertEqual(TranslationSpeechLanguage.voiceGroup("zh-CN"), "zh-TW")
        XCTAssertNil(TranslationSpeechLanguage.matchingVoiceLanguage("yue-HK", available: ["zh-TW", "zh-CN"]))
        XCTAssertNil(TranslationSpeechLanguage.matchingVoiceLanguage("zh-TW", available: ["yue-HK", "zh-HK"]))
        XCTAssertEqual(TranslationSpeechLanguage.matchingVoiceLanguage("yue-HK", available: ["zh-CN", "zh-HK"]), "zh-HK")
        XCTAssertEqual(TranslationSpeechLanguage.matchingVoiceLanguage("en-US", available: ["ja-JP", "en-GB"]), "en-GB")
        XCTAssertEqual(TranslationSpeechLanguage.preferred(for: "word", language: "en", chineseVoice: "yue-HK"), "en-US")
        XCTAssertEqual(TranslationSpeechLanguage.preferred(for: "文字", language: "zh-Hant", chineseVoice: "zh-TW"), "zh-TW")
        XCTAssertEqual(TranslationSpeechPreferences.voiceSelections(["en": "fixture.voice", "ja": 7, "fr": "other", "zh-TW": ""]), ["en": "fixture.voice"])
        for value in [Double.nan, .infinity, -.infinity, 0, -1] { XCTAssertEqual(TranslationSpeechPreferences.rate(value), 0.5) }
        XCTAssertEqual(TranslationSpeechPreferences.rate(0.1), 0.25)
        XCTAssertEqual(TranslationSpeechPreferences.rate(8), 0.65)
        for group in TranslationSpeechLanguage.voiceGroups { XCTAssertNotNil(TranslationSpeechLanguage.sampleText(group)) }
        XCTAssertNil(TranslationSpeechLanguage.sampleText("unknown"))
    }
}
