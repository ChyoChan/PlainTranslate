// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ChyoChan

import AppKit
import XCTest

@MainActor
func prepareBrandMarkForUITests() throws {
    guard NSImage(named: "BrandMarkTemplate") == nil else { return }
    // SwiftPM tests do not run inside the app bundle assembled by build.sh.
    let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Resources/Brand")
    let mark = try XCTUnwrap(NSImage(contentsOf: resources.appendingPathComponent("BrandMarkTemplate@2x.png")))
    mark.size = NSSize(width: 18, height: 18)
    mark.isTemplate = true
    XCTAssertTrue(mark.setName("BrandMarkTemplate"))
}
