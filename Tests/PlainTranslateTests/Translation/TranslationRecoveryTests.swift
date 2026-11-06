// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ChyoChan

import XCTest
@testable import PlainTranslate

final class TranslationRecoveryTests: XCTestCase {
    @MainActor
    func testCredentialFailuresOfferSetupAndOtherErrorsDoNot() throws {
        try withAppleFixture {
            for failure in [GoogleTranslationError.missingKey, .invalidKey, .denied, .quota, .network, .unavailable] {
                let model = TranslationService(presentation: .compact)
                model.input = "Sample text."
                model.translate()
                let request = try XCTUnwrap(model.request)
                model.finish(request.id, result: .failure(failure))
                XCTAssertEqual(model.googleFailure, failure)
                XCTAssertEqual(model.offersGoogleKeySetup, [.missingKey, .invalidKey, .denied].contains(failure))
                XCTAssertFalse(model.busy)
                XCTAssertNotNil(model.message)
                model.hideForSettings()
                XCTAssertEqual(model.input, "Sample text.")
                XCTAssertEqual(model.googleFailure, failure, "Opening settings must retain the original failure and input")
                model.close()
                XCTAssertNil(model.googleFailure)
                XCTAssertFalse(model.offersGoogleKeySetup)
            }
        }
    }

    @MainActor
    func testEditingCancellationAndNewRequestsClearRecoveryState() throws {
        try withAppleFixture {
            for action in 0..<3 {
                let model = TranslationService()
                model.input = "Sample text."
                model.translate()
                let request = try XCTUnwrap(model.request)
                model.finish(request.id, result: .failure(GoogleTranslationError.missingKey))
                XCTAssertTrue(model.offersGoogleKeySetup)
                switch action {
                case 0: model.inputDidChange()
                case 1: model.cancel()
                default: model.translate()
                }
                XCTAssertNil(model.googleFailure)
                XCTAssertFalse(model.offersGoogleKeySetup)
                model.finish(request.id, result: .failure(GoogleTranslationError.missingKey))
                XCTAssertNil(model.googleFailure, "A stale completion must not restore the setup action")
                model.close()
            }
        }
    }

    @MainActor
    func testSuccessfulRetryAndLocalValidationCannotKeepAnOldKeyError() throws {
        try withAppleFixture {
            let model = TranslationService()
            model.input = "Sample text."
            model.translate()
            model.finish(try XCTUnwrap(model.request).id, result: .failure(GoogleTranslationError.invalidKey))
            model.translate()
            model.finish(try XCTUnwrap(model.request).id, result: .success("示例文字。"))
            XCTAssertNil(model.googleFailure)
            XCTAssertFalse(model.offersGoogleKeySetup)
            XCTAssertEqual(model.output, "示例文字。")
            model.input = ""
            model.translate()
            XCTAssertFalse(model.offersGoogleKeySetup)
            model.close()
        }
    }

    @MainActor
    private func withAppleFixture(_ check: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let previous = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var fixture = previous
        fixture[DefaultsKey.translationEngine] = TranslationEngine.apple.rawValue
        defaults.setVolatileDomain(fixture, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }
        try check()
    }
}
