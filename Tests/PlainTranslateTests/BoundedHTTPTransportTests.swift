// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import Foundation
import XCTest
@testable import PlainTranslate

final class BoundedHTTPTransportTests: XCTestCase {
    private enum FixtureError: Error, Equatable { case invalidResponse }

    private func fetch(_ fixture: ResponseFixture, limit: Int,
                       invalidResponse: Error = FixtureError.invalidResponse) async throws -> (Data, HTTPURLResponse) {
        ResponseProtocol.register(fixture)
        defer { ResponseProtocol.remove(fixture) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResponseProtocol.self]
        var request = URLRequest(url: fixture.url)
        request.setValue("fixture_NOT_REAL", forHTTPHeaderField: "X-Goog-Api-Key")
        return try await BoundedHTTPTransport.data(for: request, configuration: configuration,
                                                   maximumBytes: limit, invalidResponse: invalidResponse)
    }

    func testSmallAndExactLimitsAreAcceptedWithAndWithoutContentLength() async throws {
        for limit in [2_000_000, 3_000_000] {
            for count in [17, limit] {
                let fixture = ResponseFixture(byteCount: count,
                                              headers: count == limit ? ["Content-Length": "\(count)"] : [:])
                let (body, response) = try await fetch(fixture, limit: limit)
                XCTAssertEqual(body, Data(repeating: 32, count: count))
                XCTAssertEqual(response.statusCode, 200)
                XCTAssertEqual(fixture.sentBytes, count)
            }
        }
    }

    func testAnnouncedOversizedBodiesAreRejectedBeforeReceivingData() async {
        for limit in [2_000_000, 3_000_000] {
            let fixture = ResponseFixture(byteCount: limit * 2, headers: ["Content-Length": "\(limit + 1)"])
            do { _ = try await fetch(fixture, limit: limit); XCTFail("Oversized response accepted") }
            catch { XCTAssertEqual(error as? FixtureError, .invalidResponse) }
            XCTAssertLessThan(fixture.sentBytes, limit)
        }
    }

    func testMissingOrDishonestContentLengthCannotBypassStreamingLimit() async {
        for limit in [2_000_000, 3_000_000] {
            for headers in [[:], ["Content-Length": "1"]] {
                let fixture = ResponseFixture(byteCount: limit * 2, headers: headers)
                do { _ = try await fetch(fixture, limit: limit); XCTFail("Oversized stream accepted") }
                catch { XCTAssertEqual(error as? FixtureError, .invalidResponse) }
                XCTAssertLessThan(fixture.sentBytes, fixture.byteCount, "Cancel before the whole body is consumed")
                XCTAssertLessThanOrEqual(fixture.sentBytes, limit + ResponseProtocol.chunkSize)
            }
        }
    }

    func testRedirectsAreRefusedWithoutSendingHeadersToTheNewHost() async {
        let fixture = ResponseFixture(byteCount: 0, redirects: true)
        do { _ = try await fetch(fixture, limit: 2_000_000); XCTFail("Redirect produced a response body") }
        catch { XCTAssertEqual(error as? FixtureError, .invalidResponse) }
        XCTAssertEqual(fixture.requestURLs, [fixture.url])
    }

    func testCancellationBeforeStartMakesNoRequest() async {
        let fixture = ResponseFixture(byteCount: 32)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await fetch(fixture, limit: 2_000_000)
        }
        do { _ = try await task.value; XCTFail("Cancelled request returned") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(fixture.requestURLs.isEmpty)
    }

    func testCancellationDuringReceiptStopsTheTask() async {
        let started = expectation(description: "Dummy response started")
        let fixture = ResponseFixture(byteCount: 2_000_000, started: { started.fulfill() })
        let task = Task { try await fetch(fixture, limit: 2_000_000) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled response returned") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertGreaterThan(fixture.sentBytes, 0)
        XCTAssertLessThan(fixture.sentBytes, fixture.byteCount)
    }

    func testGoogleOverflowKeepsSafeErrorAndOneUsageAttempt() async {
        let fixture = ResponseFixture(byteCount: 4_000_000)
        var usage: [Int] = []
        let client = GoogleTranslationClient(recordUsage: { usage.append($0) }) { _ in
            try await self.fetch(fixture, limit: 2_000_000, invalidResponse: GoogleTranslationError.invalidResponse)
        }
        do {
            _ = try await client.translate(TranslationRequest(text: "Hello", source: "en", target: "ja"),
                                           key: "fixture_NOT_REAL")
            XCTFail("Oversized response returned translation")
        } catch { XCTAssertEqual(error as? GoogleTranslationError, .invalidResponse) }
        XCTAssertEqual(usage, [5])
        XCTAssertLessThan(fixture.sentBytes, fixture.byteCount)
    }

    func testGitHubOverflowKeepsSafeError() async {
        let fixture = ResponseFixture(byteCount: 6_000_000)
        let client = GitHubReleaseClient(repository: "ChyoChan/PlainTranslate") { _ in
            try await self.fetch(fixture, limit: 3_000_000, invalidResponse: ReleaseCheckError.invalidResponse)
        }
        do { _ = try await client.latest(); XCTFail("Oversized response returned releases") }
        catch { XCTAssertEqual(error as? ReleaseCheckError, .invalidResponse) }
        XCTAssertLessThan(fixture.sentBytes, fixture.byteCount)
    }
}

private final class ResponseFixture: @unchecked Sendable {
    let url = URL(string: "https://response.invalid/\(UUID().uuidString)")!
    let byteCount: Int
    let headers: [String: String]
    let redirects: Bool
    let started: (() -> Void)?
    private let lock = NSLock()
    private var bytes = 0
    private var requests: [URL] = []
    var sentBytes: Int { lock.withLock { bytes } }
    var requestURLs: [URL] { lock.withLock { requests } }

    init(byteCount: Int, headers: [String: String] = [:], redirects: Bool = false, started: (() -> Void)? = nil) {
        self.byteCount = byteCount
        self.headers = headers
        self.redirects = redirects
        self.started = started
    }
    func sent(_ count: Int) { lock.withLock { bytes += count } }
    func received(_ url: URL) { lock.withLock { requests.append(url) } }
}

private final class ResponseProtocol: URLProtocol, @unchecked Sendable {
    static let chunkSize = 64_000
    private static let fixturesLock = NSLock()
    private static var fixtures: [String: ResponseFixture] = [:]
    private let stateLock = NSLock()
    private var stopped = false
    private let queue = DispatchQueue(label: "PlainTranslate.DummyHTTPResponse")

    static func register(_ fixture: ResponseFixture) { fixturesLock.withLock { fixtures[fixture.url.path] = fixture } }
    static func remove(_ fixture: ResponseFixture) { _ = fixturesLock.withLock { fixtures.removeValue(forKey: fixture.url.path) } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let fixture = Self.fixturesLock.withLock({ Self.fixtures[url.path] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        fixture.received(url)
        queue.async {
            guard !self.stateLock.withLock({ self.stopped }) else { return }
            if fixture.redirects {
                let destination = URL(string: "https://redirect.invalid\(url.path)")!
                let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil,
                                               headerFields: ["Location": destination.absoluteString])!
                self.client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: destination), redirectResponse: response)
                self.client?.urlProtocolDidFinishLoading(self)
                return
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: fixture.headers)!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.send(fixture, offset: 0)
        }
    }

    private func send(_ fixture: ResponseFixture, offset: Int) {
        queue.asyncAfter(deadline: .now() + .milliseconds(3)) {
            guard !self.stateLock.withLock({ self.stopped }) else { return }
            guard offset < fixture.byteCount else {
                self.client?.urlProtocolDidFinishLoading(self)
                return
            }
            let count = min(Self.chunkSize, fixture.byteCount - offset)
            fixture.sent(count)
            self.client?.urlProtocol(self, didLoad: Data(repeating: 32, count: count))
            if offset == 0 { fixture.started?() }
            self.send(fixture, offset: offset + count)
        }
    }

    override func stopLoading() { stateLock.withLock { stopped = true } }
}
