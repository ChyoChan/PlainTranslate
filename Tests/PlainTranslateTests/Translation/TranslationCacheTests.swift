// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import PlainTranslate

final class TranslationCacheTests: XCTestCase {
    func testBoundedSessionCacheKeysAndEviction() { TranslationCacheChecks.run { XCTAssertTrue($0, $1) } }
    @MainActor func testServiceCacheLifecycleAndGoogleAccounting() async {
        await TranslationCacheServiceChecks.run { XCTAssertTrue($0, $1) }
    }
}
