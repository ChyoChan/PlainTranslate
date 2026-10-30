// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import PlainTranslate

final class ReleaseUpdateTests: XCTestCase {
    @MainActor func testPublishedReleaseChecks() async {
        await ReleaseUpdateChecks.run { XCTAssertTrue($0, $1) }
    }
}
