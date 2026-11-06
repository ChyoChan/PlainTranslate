// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import AppKit
import Carbon.HIToolbox
import XCTest
@testable import PlainTranslate

final class TranslationShortcutTests: XCTestCase {
    @MainActor
    func testRecorderCapturesACombinationAndEscapeCancelsWithoutChangingIt() throws {
        _ = NSApplication.shared
        let button = TranslationShortcutRecorder.RecorderButton(frame: NSRect(x: 0, y: 0, width: 180, height: 30))
        let window = NSWindow(contentRect: button.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = button
        defer { window.close() }
        var captures: [TranslationShortcut] = []
        var recording: [Bool] = []
        button.capture = { captures.append($0) }
        button.recordingChanged = { recording.append($0) }
        let chosen = TranslationShortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | optionKey))
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command, .option], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "k", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: UInt16(kVK_ANSI_K)))
        button.beginRecording()
        XCTAssertEqual(button.title, "Press shortcut…")
        XCTAssertTrue(button.performKeyEquivalent(with: event))
        XCTAssertEqual(captures, [chosen])
        XCTAssertEqual(button.title, chosen.displayString)
        button.beginRecording()
        button.keyDown(with: try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)))
        XCTAssertEqual(captures, [chosen], "Escape must preserve the saved shortcut")
        XCTAssertEqual(recording, [true, false, true, false])
        XCTAssertEqual(button.title, chosen.displayString)
        XCTAssertFalse(window.isVisible)
    }

    @MainActor
    func testNativeRegistrationConflictsAndReleasesWithoutPostingKeys() {
        _ = NSApplication.shared
        let shortcut = TranslationShortcut(keyCode: UInt32(kVK_F19),
            modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey))
        let first = TranslationGlobalHotKey { XCTFail("No keyboard events should be generated") }
        let second = TranslationGlobalHotKey { XCTFail("No keyboard events should be generated") }
        defer { first.update(shortcut: nil); second.update(shortcut: nil) }
        XCTAssertTrue(first.update(shortcut: shortcut))
        XCTAssertTrue(first.update(shortcut: shortcut), "Unchanged registration should be reused")
        XCTAssertFalse(second.update(shortcut: shortcut))
        XCTAssertTrue(first.update(shortcut: nil))
        XCTAssertTrue(second.update(shortcut: shortcut))
        XCTAssertTrue(second.update(shortcut: nil))
        XCTAssertTrue(first.update(shortcut: shortcut))
    }

    func testShortcutsRequireModifiersAndRejectUnsafeOrUnsupportedKeys() {
        XCTAssertTrue(TranslationShortcut.defaultValue.isValid)
        XCTAssertFalse(TranslationShortcut(keyCode: 17, modifiers: 0).isValid)
        XCTAssertFalse(TranslationShortcut(keyCode: 17, modifiers: UInt32(shiftKey)).isValid)
        XCTAssertFalse(TranslationShortcut(keyCode: 999, modifiers: UInt32(cmdKey)).isValid)
        XCTAssertFalse(TranslationShortcut(keyCode: 17, modifiers: UInt32(cmdKey) | (1 << 30)).isValid)
        for key: UInt32 in [0, 6, 7, 8, 9, 12, 13, 36, 43, 48, 49] {
            XCTAssertFalse(TranslationShortcut(keyCode: key, modifiers: UInt32(cmdKey)).isValid)
        }
        XCTAssertFalse(TranslationShortcut(keyCode: 53, modifiers: UInt32(cmdKey | optionKey)).isValid)
        XCTAssertTrue(TranslationShortcut(keyCode: 17, modifiers: UInt32(cmdKey | shiftKey)).isValid)
        XCTAssertTrue(TranslationShortcut(keyCode: 123, modifiers: UInt32(controlKey | optionKey)).isValid)
    }

    func testShortcutPreferencesRoundTripAndMalformedOrInvalidValuesFallBack() throws {
        let domain = "PlainTranslate-shortcut-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        XCTAssertEqual(TranslationShortcut.load(from: defaults), .defaultValue)
        let chosen = TranslationShortcut(keyCode: 40, modifiers: UInt32(cmdKey | optionKey))
        chosen.save(to: defaults)
        XCTAssertEqual(TranslationShortcut.load(from: defaults), chosen)
        TranslationShortcut(keyCode: 8, modifiers: UInt32(cmdKey)).save(to: defaults)
        XCTAssertEqual(TranslationShortcut.load(from: defaults), chosen)
        defaults.set(Data("bad json".utf8), forKey: DefaultsKey.translationShortcut)
        XCTAssertEqual(TranslationShortcut.load(from: defaults), .defaultValue)
        let invalid = TranslationShortcut(keyCode: 17, modifiers: 0)
        defaults.set(try JSONEncoder().encode(invalid), forKey: DefaultsKey.translationShortcut)
        XCTAssertEqual(TranslationShortcut.load(from: defaults), .defaultValue)
    }

    func testModifierConversionAndDisplay() throws {
        XCTAssertEqual(TranslationShortcut.defaultValue.displayString, "⌃⌥T")
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command, .control, .option, .shift, .capsLock], timestamp: 0,
            windowNumber: 0, context: nil, characters: "T", charactersIgnoringModifiers: "t",
            isARepeat: false, keyCode: UInt16(kVK_ANSI_T)))
        let shortcut = TranslationShortcut(event: event)
        XCTAssertEqual(shortcut.modifiers, UInt32(cmdKey | controlKey | optionKey | shiftKey))
        XCTAssertEqual(shortcut.displayString, "⌃⌥⇧⌘T")
    }
}
