// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import AppKit
import SwiftUI
import XCTest
@testable import PlainTranslate

final class TranslationSetupTests: XCTestCase {
    func testDownloadsRequireTwoExplicitSupportedDifferentLanguages() {
        for source in ["auto", "en", "zh-Hant", "ja", "unknown"] {
            for target in ["auto", "en", "zh-Hant", "ja", "unknown"] {
                let pair = AppleSetupPair(source: source, target: target)
                let allowed = source != target && ["en", "zh-Hant", "ja"].contains(source) && ["en", "zh-Hant", "ja"].contains(target)
                XCTAssertEqual(pair.isSupportedChoice, allowed)
                XCTAssertEqual(pair.configuration != nil, allowed)
            }
        }
    }

}
