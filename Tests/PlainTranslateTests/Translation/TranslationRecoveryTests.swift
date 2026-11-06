// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ChyoChan

import XCTest
import Translation
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
    func testFailuresOfferUsefulRecoveryWithoutDisplayingRawErrors() throws {
        try withAppleFixture {
            var failures: [(Error, Bool)] = [
                (GoogleTranslationError.network, true), (.unavailable as GoogleTranslationError, true),
                (.invalidResponse as GoogleTranslationError, true), (.quota as GoogleTranslationError, true),
                (.missingKey as GoogleTranslationError, false), (.invalidKey as GoogleTranslationError, false),
                (.denied as GoogleTranslationError, false), (.invalidRequest as GoogleTranslationError, false),
                (.requestTooLarge as GoogleTranslationError, false),
                (TranslationKeychain.Failure(), true), (URLError(.notConnectedToInternet), true),
                (TranslationError.internalError, true),
                (TranslationError.unsupportedSourceLanguage, false),
                (TranslationError.unsupportedTargetLanguage, false),
                (TranslationError.unsupportedLanguagePairing, false),
                (TranslationError.unableToIdentifyLanguage, false), (TranslationError.nothingToTranslate, false),
                (TranslationInputError.tooLong, false), (TranslationInputError.sensitive, false),
                (TranslationInputError.clipboardChanged, false),
                (NSError(domain: "private", code: 1, userInfo: [NSLocalizedDescriptionKey: "SECRET_TEXT_AND_KEY"]), true),
            ]
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) { failures.append((TranslationError.notInstalled, true)) }
            #endif
            for (failure, retryable) in failures {
                let model = TranslationService()
                defer { model.close() }
                model.input = "A complete sentence."
                model.translate()
                model.finish(try XCTUnwrap(model.request).id, result: .failure(failure))
                XCTAssertFalse(model.busy)
                XCTAssertEqual(model.canRetry, retryable, "Wrong recovery for \(type(of: failure))")
                XCTAssertFalse(try XCTUnwrap(model.message).contains("SECRET_TEXT_AND_KEY"))
                XCTAssertEqual(model.input, "A complete sentence.")
                if !retryable {
                    model.retryTranslation()
                    XCTAssertNil(model.request, "Fix input or configuration before resubmitting")
                }
            }
        }
    }

    @MainActor
    func testManualRetryPreservesRequestAndIgnoresDuplicateClicksAndOldResults() throws {
        try withAppleFixture {
            let model = TranslationService()
            defer { model.close() }
            model.input = "Original text."
            model.translate()
            let first = try XCTUnwrap(model.request)
            model.finish(first.id, result: .failure(TranslationError.internalError))
            XCTAssertTrue(model.canRetry)
            model.retryTranslation()
            let retry = try XCTUnwrap(model.request)
            XCTAssertNotEqual(first.id, retry.id)
            XCTAssertEqual(retry.text, first.text)
            XCTAssertEqual(retry.source, first.source)
            XCTAssertEqual(retry.target, first.target)
            XCTAssertEqual(retry.engine, first.engine)
            XCTAssertFalse(model.canRetry)
            XCTAssertTrue(model.busy)
            XCTAssertNil(model.message)
            model.retryTranslation()
            XCTAssertEqual(model.request?.id, retry.id)
            model.finish(first.id, result: .failure(GoogleTranslationError.invalidKey))
            XCTAssertNil(model.message)
            XCTAssertNil(model.googleFailure)
            model.finish(retry.id, result: .success("原文。"))
            XCTAssertEqual(model.output, "原文。")
            XCTAssertFalse(model.canRetry)
            model.finish(first.id, result: .failure(TranslationError.internalError))
            XCTAssertFalse(model.canRetry)
            XCTAssertEqual(model.output, "原文。")
        }
    }

    @MainActor
    func testCancellationAndChangesRemoveRetryState() throws {
        try withAppleFixture {
            var cancellations: [Error] = [CancellationError(), URLError(.cancelled)]
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) { cancellations.append(TranslationError.alreadyCancelled) }
            #endif
            for failure in cancellations {
                let model = TranslationService()
                defer { model.close() }
                model.input = "Sample text."
                model.translate()
                model.finish(try XCTUnwrap(model.request).id, result: .failure(failure))
                XCTAssertNil(model.message)
                XCTAssertFalse(model.canRetry)
            }
            for action in 0..<5 {
                let model = TranslationService()
                defer { model.close() }
                model.input = "Sample text."
                model.translate()
                model.finish(try XCTUnwrap(model.request).id, result: .failure(GoogleTranslationError.network))
                XCTAssertTrue(model.canRetry)
                switch action {
                case 0: model.inputDidChange()
                case 1: model.cancel()
                case 2: model.close()
                case 3: model.input = ""; model.translate()
                default: model.setTarget(model.target == "ja" ? "en" : "ja")
                }
                XCTAssertFalse(model.canRetry)
            }
        }
    }

    @MainActor
    func testGoogleRetriesOnlyOnExplicitActionWithoutSwitchingEngines() async throws {
        let defaults = UserDefaults.standard
        let previous = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var fixture = previous
        fixture[DefaultsKey.translationEngine] = TranslationEngine.google.rawValue
        defaults.setVolatileDomain(fixture, forName: UserDefaults.argumentDomain)
        var submissions: [TranslationRequest] = []
        let model = TranslationService(googleTranslation: { request in
            submissions.append(request)
            if submissions.count == 1 { throw GoogleTranslationError.network }
            return "Google fixture result"
        })
        defer {
            model.close()
            defaults.setVolatileDomain(previous, forName: UserDefaults.argumentDomain)
        }
        model.input = "Only send again when I retry."
        model.translate()
        try await waitUntilIdle(model)
        XCTAssertTrue(model.canRetry)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(submissions.count, 1, "No automatic retry is allowed")
        model.retryTranslation()
        model.retryTranslation()
        try await waitUntilIdle(model)
        XCTAssertEqual(submissions.count, 2)
        XCTAssertTrue(submissions.allSatisfy { $0.engine == .google })
        XCTAssertEqual(submissions.first?.text, submissions.last?.text)
        XCTAssertEqual(model.output, "Google fixture result")
        XCTAssertFalse(model.canRetry)
    }

    @MainActor
    func testGoogleResponseReasonsReachTheCorrectRecoveryActions() async throws {
        let defaults = UserDefaults.standard
        let previous = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var fixture = previous
        fixture[DefaultsKey.translationEngine] = TranslationEngine.google.rawValue
        defaults.setVolatileDomain(fixture, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }
        let fixtures: [(Int, String, GoogleTranslationError)] = [
            (403, #"{"error":{"errors":[{"reason":"dailyLimitExceeded"}]}}"#, .quota),
            (400, #"{"error":{"details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"API_KEY_INVALID"}]}}"#, .invalidKey),
            (403, #"{"error":{"errors":[{"reason":"accessNotConfigured"}]}}"#, .denied),
        ]
        for (status, body, expected) in fixtures {
            var calls = 0
            let client = GoogleTranslationClient(recordUsage: { _ in }) { http in
                calls += 1
                return (Data(body.utf8), HTTPURLResponse(url: http.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
            let model = TranslationService(googleTranslation: { request in
                try await client.translate(request, key: "fixture_NOT_REAL_123")
            })
            defer { model.close() }
            model.input = "A complete sentence."
            model.translate()
            try await waitUntilIdle(model)
            XCTAssertEqual(model.googleFailure, expected)
            XCTAssertEqual(model.canRetry, expected == .quota)
            XCTAssertEqual(model.offersGoogleKeySetup, expected != .quota)
            XCTAssertEqual(model.input, "A complete sentence.")
            XCTAssertEqual(calls, 1, "Recovery must wait for an explicit user action")
        }
    }

    @MainActor
    private func waitUntilIdle(_ model: TranslationService) async throws {
        let deadline = Date().addingTimeInterval(2)
        while model.busy, Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertFalse(model.busy, "The fake provider should have completed")
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
