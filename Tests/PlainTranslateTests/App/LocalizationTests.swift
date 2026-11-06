// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import XCTest
@testable import PlainTranslate

final class LocalizationTests: XCTestCase {
    func testSystemPreferenceOrderAndChineseScriptAreRespected() {
        let fixtures: [([String], AppLanguage)] = [
            ([], .en), (["fr-FR"], .en), (["en-GB", "ja-JP"], .en),
            (["ja-JP", "en-US"], .ja), (["fr-FR", "ja"], .ja),
            (["zh-Hans", "en"], .zhHans), (["zh-CN"], .zhHans),
            (["zh-SG"], .zhHans), (["zh-Hans-TW"], .zhHans),
            (["zh-TW"], .zhTW), (["zh-Hant-TW"], .zhTW),
            (["zh-HK"], .zhHK), (["zh-MO"], .zhHK), (["zh-Hant"], .zhHK),
            (["ja", "zh-Hans"], .ja), (["zh-Hans", "ja"], .zhHans),
        ]
        for (identifiers, expected) in fixtures {
            XCTAssertEqual(AppLanguage.preferred(in: identifiers), expected, identifiers.joined(separator: ","))
        }
        XCTAssertEqual(AppLanguage.allCases.map(\.rawValue), ["en", "zh-HK", "zh-TW", "zh-Hans", "ja"])
        XCTAssertEqual(AppLanguage.zhHans.displayName, "简体中文")
        XCTAssertEqual(AppLanguage.ja.displayName, "日本語")
    }

    func testNewLocalesCoverTranslationRecoveryPrivacyAndSetup() {
        let hans = TranslationStrings(language: .zhHans)
        let ja = TranslationStrings(language: .ja)
        XCTAssertEqual(hans.title, "翻译")
        XCTAssertEqual(ja.title, "翻訳")
        XCTAssertEqual(hans.copy, "复制译文")
        XCTAssertEqual(ja.retry, "再試行")
        XCTAssertEqual(ja.cacheCount(7), "7 件の結果をキャッシュ済み")
        XCTAssertTrue(hans.googlePrivacy.contains("自动"))
        XCTAssertTrue(ja.googlePrivacy.contains("自動送信"))
        XCTAssertTrue(hans.clipboardChanged.contains("剪贴板"))
        XCTAssertTrue(ja.clipboardChanged.contains("クリップボード"))
        XCTAssertTrue(hans.languagesNotInstalled.contains("语言包"))
        XCTAssertTrue(ja.languagesNotInstalled.contains("言語パック"))
        for language in [AppLanguage.zhHans, .ja] {
            let text = TranslationStrings(language: language)
            let en = TranslationStrings(language: .en)
            for error in [GoogleTranslationError.missingKey, .invalidKey, .denied, .quota, .network,
                          .invalidRequest, .requestTooLarge, .invalidResponse, .unavailable] {
                XCTAssertFalse(text.googleError(error).isEmpty)
                XCTAssertNotEqual(text.googleError(error), en.googleError(error))
            }
            for step in GoogleSetupStep.allCases {
                XCTAssertNotEqual(step.title(language), step.title(.en))
                XCTAssertNotEqual(step.instructions(language), step.instructions(.en))
                XCTAssertNotEqual(step.title(language), step.title(.zhHK))
            }
        }
        XCTAssertEqual(TranslationStrings(language: .zhHK).privacy, TranslationStrings(language: .zhTW).privacy)
    }
}
