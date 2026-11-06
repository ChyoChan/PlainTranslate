// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import Security
import XCTest
@testable import PlainTranslate

final class TranslationKeychainTests: XCTestCase {
    func testExistingItemIsNotOverwrittenAndExplicitReplacementWorks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PlainTranslate-Keychain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("fixture.keychain").path
        var keychain: SecKeychain?
        let password = Array("fixture-password".utf8)
        let status = password.withUnsafeBytes {
            SecKeychainCreate(path, UInt32($0.count), $0.baseAddress, false, nil, &keychain)
        }
        XCTAssertEqual(status, errSecSuccess)
        let isolated = try XCTUnwrap(keychain)
        defer { XCTAssertEqual(SecKeychainDelete(isolated), errSecSuccess) }
        let service = "test.plaintranslate.\(UUID().uuidString)"
        let existing: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "api-key",
            kSecAttrSynchronizable as String: false, kSecUseKeychain as String: isolated,
            kSecValueData as String: Data("fixture_original".utf8)]
        XCTAssertEqual(SecItemAdd(existing as CFDictionary, nil), errSecSuccess)
        let store = TranslationKeychain(service: service, keychain: isolated)
        XCTAssertThrowsError(try store.save("fixture_new")) { error in
            XCTAssertTrue(error is TranslationKeychain.ExistingItem)
        }
        XCTAssertEqual(try store.load(), "fixture_original")
        XCTAssertThrowsError(try store.save("invalid key"))
        XCTAssertEqual(try store.load(), "fixture_original")
        XCTAssertTrue(try store.contains())
        try store.remove()
        XCTAssertFalse(try store.contains())
        try store.save("fixture_new")
        XCTAssertEqual(try store.load(), "fixture_new")
        XCTAssertThrowsError(try store.save("fixture_another"))
        XCTAssertEqual(try store.load(), "fixture_new")
        try store.remove()
        XCTAssertNil(try store.load())
    }
}
