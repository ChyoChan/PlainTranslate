// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import AppKit
import SwiftUI
import XCTest
@testable import PlainTranslate

final class TranslationSetupTests: XCTestCase {
    func testDownloadsRequireTwoExplicitSupportedDifferentLanguages() {
        for source in ["auto", "en", "zh-Hant", "ja", "zh-Hans", "unknown"] {
            for target in ["auto", "en", "zh-Hant", "ja", "zh-Hans", "unknown"] {
                let pair = AppleSetupPair(source: source, target: target)
                let allowed = source != target && ["en", "zh-Hant", "ja", "zh-Hans"].contains(source) && ["en", "zh-Hant", "ja", "zh-Hans"].contains(target)
                XCTAssertEqual(pair.isSupportedChoice, allowed)
                XCTAssertEqual(pair.configuration != nil, allowed)
            }
        }
    }

    func testGoogleGuideLinksOnlyToRelevantOfficialConsolePages() {
        XCTAssertEqual(GoogleSetupStep.allCases.count, 5)
        for step in GoogleSetupStep.allCases {
            if step == .save { XCTAssertNil(step.url) }
            else {
                XCTAssertEqual(step.url?.scheme, "https")
                XCTAssertEqual(step.url?.host, "console.cloud.google.com")
                XCTAssertNil(step.url?.user)
                XCTAssertNil(step.url?.query)
            }
            for language in AppLanguage.allCases {
                XCTAssertFalse(step.title(language).isEmpty)
                XCTAssertFalse(step.instructions(language).isEmpty)
            }
        }
        XCTAssertEqual(GoogleSetupStep.api.url?.lastPathComponent, "translate.googleapis.com")
    }

    @MainActor
    func testGuidesRenderWithoutStartingDownloadsOrOpeningBrowser() throws {
        _ = NSApplication.shared
        for language in AppLanguage.allCases {
            let content = VStack {
                AppleLanguagePackSetup(language: language)
                GoogleAPISetupGuide(language: language)
            }.padding().frame(width: 600)
            let host = NSHostingView(rootView: content)
            host.setFrameSize(NSSize(width: 600, height: 240))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            XCTAssertGreaterThan(try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).count, 1000)
        }
    }
}
