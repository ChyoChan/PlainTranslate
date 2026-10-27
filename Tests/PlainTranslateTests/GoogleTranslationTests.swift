// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Copyright (C) 2026 PlainTranslate contributors

import XCTest
@testable import PlainTranslate

final class GoogleTranslationTests: XCTestCase {
    private let fakeKey = "fixture_NOT_REAL_12345"
    private var request: TranslationRequest { TranslationRequest(text: "Hello", source: "en", target: "zh-Hant", engine: .google) }

    func testKeyAndPayloadBoundaries() throws {
        XCTAssertEqual(try TranslationAPIKey.normalized("  fixture_key-123\n"), "fixture_key-123")
        for value in ["", " \n", "key with spaces", "key\r\nInjected: value", "金鑰", String(repeating: "x", count: 257)] {
            XCTAssertThrowsError(try TranslationAPIKey.normalized(value))
        }
        XCTAssertThrowsError(try GoogleTranslationClient.makeRequest(texts: [], source: nil, target: "ja", key: fakeKey))
        XCTAssertThrowsError(try GoogleTranslationClient.makeRequest(texts: ["one", "two"], source: nil, target: "ja", key: fakeKey))
        let http = try GoogleTranslationClient.makeRequest(texts: ["Hello"], source: nil, target: "zh-Hant", key: fakeKey)
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(http.httpBody)) as? [String: Any])
        XCTAssertEqual(http.url, GoogleTranslationClient.endpoint)
        XCTAssertEqual(http.url?.scheme, "https")
        XCTAssertNil(http.url?.query)
        XCTAssertEqual(http.value(forHTTPHeaderField: "X-Goog-Api-Key"), fakeKey)
        XCTAssertEqual(body["q"] as? [String], ["Hello"])
        XCTAssertEqual(body["target"] as? String, "zh-TW")
        XCTAssertEqual(body["format"] as? String, "text")
        XCTAssertEqual(body["model"] as? String, "nmt")
        XCTAssertNil(body["source"])
        XCTAssertNil(body["key"])
    }

    func testHTMLIsDecodedOnceAsPlainText() {
        XCTAssertEqual(GoogleTranslationClient.decodeEntities("&lt;b&gt;A &amp; B&lt;/b&gt; &#39; &#x4E2D; &amp;lt; &unknown;"),
                       "<b>A & B</b> ' 中 &lt; &unknown;")
    }

    func testWholeSelectionHasOneTransportCallAndCodepointUsage() async throws {
        let original = "中 A\n👩🏽‍💻\r\n\nSecond paragraph. "
        var calls = 0, usage: [Int] = []
        let client = GoogleTranslationClient(recordUsage: { usage.append($0) }) { http in
            calls += 1
            XCTAssertEqual(usage.count, calls)
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(http.httpBody)) as? [String: Any])
            XCTAssertEqual(body["q"] as? [String], [original])
            return (Data("{\"data\":{\"translations\":[{\"translatedText\":\"完整譯文\"}]}}".utf8),
                    HTTPURLResponse(url: http.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let translated = try await client.translate(TranslationRequest(text: original, source: "en", target: "zh-Hant", engine: .google), key: fakeKey)
        XCTAssertEqual(translated, "完整譯文")
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(usage, [original.unicodeScalars.count])
    }

    func testHTTPFailuresAreSanitizedAndNeverRetried() async {
        for (status, expected) in [(400, GoogleTranslationError.invalidRequest), (401, .invalidKey), (403, .denied),
                                   (429, .quota), (503, .unavailable), (302, .invalidResponse)] {
            var calls = 0, submissions = 0
            let client = GoogleTranslationClient(recordUsage: { _ in submissions += 1 }) { http in
                calls += 1
                return (Data("private server details must not become UI errors".utf8),
                        HTTPURLResponse(url: http.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
            do { _ = try await client.translate(request, key: fakeKey); XCTFail("HTTP failure returned output") }
            catch { XCTAssertEqual(error as? GoogleTranslationError, expected) }
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(submissions, 1)
        }
    }

    func testMalformedResponseCannotPublishPartialSuccess() async {
        for body in ["{}", "{\"data\":{\"translations\":[]}}", "not JSON", "{\"data\":{\"translations\":[{},{}]}}"] {
            let client = GoogleTranslationClient(recordUsage: { _ in }) { http in
                (Data(body.utf8), HTTPURLResponse(url: http.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            do { _ = try await client.translate(request, key: fakeKey); XCTFail("Malformed result accepted") }
            catch { XCTAssertEqual(error as? GoogleTranslationError, .invalidResponse) }
        }
    }

    func testInvalidRequestsNeverSendOrIncreaseUsage() async {
        var calls = 0, submissions = 0
        let client = GoogleTranslationClient(recordUsage: { _ in submissions += 1 }) { _ in
            calls += 1
            throw URLError(.notConnectedToInternet)
        }
        for (text, key) in [("Hello", ""), ("Hello", "bad key"), (" \n", fakeKey),
                            (String(repeating: "x", count: 40_001), fakeKey),
                            (String(repeating: "字", count: 34_000), fakeKey),
                            (String(repeating: "\u{0000}", count: 20_000), fakeKey),
                            (String(repeating: "👩🏽‍💻", count: 10_001), fakeKey)] {
            do { _ = try await client.translate(TranslationRequest(text: text, source: nil, target: "ja"), key: key); XCTFail("Invalid request accepted") }
            catch { /* Local validation must complete before either callback. */ }
        }
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(submissions, 0)
    }

    func testCancellationBeforeAndAfterTransport() async {
        var calls = 0, submissions = 0
        let client = GoogleTranslationClient(recordUsage: { _ in submissions += 1 }) { http in
            calls += 1
            withUnsafeCurrentTask { $0?.cancel() }
            return (Data("{\"data\":{\"translations\":[{\"translatedText\":\"stale\"}]}}".utf8),
                    HTTPURLResponse(url: http.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let before = Task { () throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.translate(self.request, key: self.fakeKey)
        }
        do { _ = try await before.value; XCTFail("Pre-cancelled task returned") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(submissions, 0)
        let during = Task { try await client.translate(self.request, key: self.fakeKey) }
        do { _ = try await during.value; XCTFail("In-flight cancellation returned output") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(submissions, 1)
    }

    func testNetworkFailureCountsAttemptAndShowsSafeError() async {
        var count = 0
        let client = GoogleTranslationClient(recordUsage: { _ in count += 1 }) { _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await client.translate(request, key: fakeKey); XCTFail("Offline request returned") }
        catch { XCTAssertEqual(error as? GoogleTranslationError, .network) }
        XCTAssertEqual(count, 1)
    }

    func testTransportCancellationCountsOneAttemptWithoutRetry() async {
        var calls = 0, submissions = 0
        let client = GoogleTranslationClient(recordUsage: { _ in submissions += 1 }) { _ in
            calls += 1
            throw URLError(.cancelled)
        }
        do { _ = try await client.translate(request, key: fakeKey); XCTFail("Cancelled transport returned output") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(submissions, 1)
    }
}
