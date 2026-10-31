// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import AppKit
import SwiftUI
import XCTest
@testable import PlainTranslate

final class SettingsNavigationTests: XCTestCase {
    @MainActor
    func testSixPanesUseOneFixedNativeToolbarAndRestoreTheSelectedPane() throws {
        _ = NSApplication.shared
        let domain = "com.chyo.plaintranslate.tests.settings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let navigation = SettingsNavigation(defaults: defaults)
        XCTAssertEqual(navigation.selectedPane, .translation)
        XCTAssertEqual(Set(SettingsPane.allCases.map(\.rawValue)),
                       ["translation", "shortcuts", "appearance", "speech", "usage", "about"])
        let window = navigation.makeWindow(inspectCredentials: false)
        defer { window.close() }
        XCTAssertFalse(window.isVisible, "Constructing settings must not show a window or inspect credentials")
        XCTAssertTrue(window === navigation.makeWindow(inspectCredentials: false))
        let controller = try XCTUnwrap(window.contentViewController as? NSTabViewController)
        XCTAssertEqual(controller.tabStyle, .toolbar)
        XCTAssertEqual(controller.tabViewItems.count, 6)
        let toolbar = try XCTUnwrap(window.toolbar)
        XCTAssertFalse(toolbar.allowsUserCustomization)
        XCTAssertEqual(window.toolbarStyle, .preference)
        XCTAssertEqual(toolbar.displayMode, .iconAndLabel)
        let back = try XCTUnwrap(toolbar.items.first { $0.itemIdentifier.rawValue == "settings.back" })
        XCTAssertNotNil(back.target)
        XCTAssertNotNil(back.action)
        XCTAssertFalse(back.label.isEmpty)

        for (index, pane) in SettingsPane.allCases.enumerated() {
            navigation.selectPane(pane)
            settle()
            XCTAssertEqual(navigation.selectedPane, pane)
            XCTAssertEqual(controller.selectedTabViewItemIndex, index)
            XCTAssertTrue(window.title.contains(pane.title(for: L10n.shared.language)))
            XCTAssertFalse(window.isVisible, "Switching settings panes never presents a hidden fixture")
            XCTAssertEqual(SettingsNavigation(defaults: defaults).selectedPane, pane,
                           "A new settings session must reopen the most recently selected pane")
        }
    }

    @MainActor
    func testNativeTabSelectionPersistsAndChangingLanguageUpdatesWindowChrome() throws {
        _ = NSApplication.shared
        let domain = "com.chyo.plaintranslate.tests.settings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let previousLanguage = L10n.shared.language
        defer {
            defaults.removePersistentDomain(forName: domain)
            L10n.shared.setLanguage(previousLanguage)
        }
        L10n.shared.setLanguage(.en)
        let navigation = SettingsNavigation(defaults: defaults)
        let window = navigation.makeWindow(inspectCredentials: false)
        defer { window.close() }
        let controller = try XCTUnwrap(window.contentViewController as? NSTabViewController)
        let appearanceIndex = try XCTUnwrap(SettingsPane.allCases.firstIndex(of: .appearance))
        controller.selectedTabViewItemIndex = appearanceIndex
        settle()
        XCTAssertEqual(navigation.selectedPane, .appearance,
                       "The actual AppKit tab controller must update the saved selection")
        XCTAssertEqual(SettingsNavigation(defaults: defaults).selectedPane, .appearance)
        XCTAssertTrue(window.title.contains(SettingsPane.appearance.title(for: .en)))
        L10n.shared.setLanguage(.zhHK)
        settle()
        XCTAssertTrue(window.title.contains(SettingsPane.appearance.title(for: .zhHK)))
        let toolbar = try XCTUnwrap(window.toolbar)
        let back = try XCTUnwrap(toolbar.items.first { $0.itemIdentifier.rawValue == "settings.back" })
        XCTAssertTrue(back.label.contains("返回"))
        XCTAssertTrue(back.label.contains("翻譯"))
        XCTAssertFalse(window.isVisible)
        for language in [AppLanguage.en, .zhHK, .zhTW] {
            XCTAssertEqual(Set(SettingsPane.allCases.map { $0.title(for: language) }).count, 6)
            XCTAssertTrue(SettingsPane.allCases.allSatisfy { !$0.title(for: language).isEmpty && !$0.symbol.isEmpty })
        }
    }

    @MainActor
    func testGoogleCredentialRecoverySelectsTranslationWithoutShowingSettingsOrStartingARequest() throws {
        let domain = "com.chyo.plaintranslate.tests.settings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let model = TranslationService.shared
        let oldEngine = model.engine
        let oldPreference = UserDefaults.standard.object(forKey: DefaultsKey.translationEngine)
        defer {
            model.setEngine(oldEngine)
            if let oldPreference { UserDefaults.standard.set(oldPreference, forKey: DefaultsKey.translationEngine) }
            else { UserDefaults.standard.removeObject(forKey: DefaultsKey.translationEngine) }
        }
        let navigation = SettingsNavigation(defaults: defaults)
        navigation.selectPane(.speech)
        navigation.prepareGoogleCredentials()
        XCTAssertEqual(navigation.selectedPane, .translation)
        XCTAssertTrue(navigation.focusGoogleCredentials)
        XCTAssertEqual(model.engine, .google)
        XCTAssertNil(model.request, "Credential setup only chooses an engine; it must not submit text")
        XCTAssertFalse(model.busy)
    }

    @MainActor
    func testNativeSettingsFramePreviewUsesOnlyItsOwnOffscreenWindow() throws {
        guard let directory = ProcessInfo.processInfo.environment["PLAINTRANSLATE_PREVIEW_DIR"] else {
            throw XCTSkip("Set PLAINTRANSLATE_PREVIEW_DIR to render native frame previews")
        }
        _ = NSApplication.shared
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let previousLanguage = L10n.shared.language
        let previousAppearance = NSApp.appearance
        defer {
            L10n.shared.setLanguage(previousLanguage)
            NSApp.appearance = previousAppearance
        }
        let cases: [(String, AppLanguage, NSAppearance.Name)] = [
            ("native-settings-hk-dark", .zhHK, .darkAqua),
            ("native-settings-en-light", .en, .aqua),
        ]
        func render(_ name: String, language: AppLanguage, appearance: NSAppearance.Name) throws {
            L10n.shared.setLanguage(language)
            NSApp.appearance = NSAppearance(named: appearance)
            let domain = "com.chyo.plaintranslate.tests.settings-frame.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
            defer { defaults.removePersistentDomain(forName: domain) }
            let navigation = SettingsNavigation(defaults: defaults)
            let window = navigation.makeWindow(inspectCredentials: false)
            defer { window.close() }
            window.appearance = NSApp.appearance
            window.setContentSize(NSSize(width: 840, height: 660))
            // Rendering uses only this fixture, never a screenshot of the desktop.
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            window.orderFront(nil)
            settle()
            XCTAssertFalse(window.isKeyWindow)
            XCTAssertEqual(window.alphaValue, 0)
            XCTAssertTrue(window.ignoresMouseEvents)
            let frame = try XCTUnwrap(window.contentView?.superview)
            frame.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let bitmap = try XCTUnwrap(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
            frame.cacheDisplay(in: frame.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(png.count, 1_000)
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
        }
        for (name, language, appearance) in cases {
            try render(name, language: language, appearance: appearance)
        }
    }

    @MainActor
    func testInactiveTranslationHostCannotConsumeTheCredentialFocusRequest() throws {
        _ = NSApplication.shared
        let domain = "com.chyo.plaintranslate.tests.settings-focus.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let model = TranslationService.shared
        let oldEngine = model.engine
        let oldPreference = UserDefaults.standard.object(forKey: DefaultsKey.translationEngine)
        defer {
            model.setEngine(oldEngine)
            if let oldPreference { UserDefaults.standard.set(oldPreference, forKey: DefaultsKey.translationEngine) }
            else { UserDefaults.standard.removeObject(forKey: DefaultsKey.translationEngine) }
        }
        let navigation = SettingsNavigation(defaults: defaults)
        navigation.prepareGoogleCredentials()
        navigation.selectPane(.speech)
        let host = NSHostingView(rootView: SettingsView(pane: .translation,
            inspectCredentials: false, navigation: navigation))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 680),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        settle()
        XCTAssertTrue(navigation.focusGoogleCredentials,
                      "A retained but inactive translation view must not steal the recovery request")
        XCTAssertEqual(navigation.selectedPane, .speech)
        XCTAssertFalse(window.isVisible)

        // Positive control: the same mounted host handles the request once selected.
        navigation.selectPane(.translation)
        navigation.focusGoogleCredentials = false
        settle()
        navigation.focusGoogleCredentials = true
        settle()
        XCTAssertFalse(navigation.focusGoogleCredentials,
                       "The selected translation pane must consume its own focus request")
        XCTAssertNil(model.request)
        XCTAssertFalse(model.busy)
        XCTAssertFalse(window.isVisible)
    }

    @MainActor
    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}
