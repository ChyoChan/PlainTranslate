// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ChyoChan

import AppKit
import SwiftUI
import XCTest
@testable import PlainTranslate

final class InterfaceTests: XCTestCase {
    @MainActor
    func testNativeInterfacesFitAndRenderWithoutNetworkOrVisibleWindows() throws {
        _ = NSApplication.shared
        try prepareBrandMarkForUITests()
        AppPreferences.registerDefaults()
        let previousLanguage = L10n.shared.language
        defer { L10n.shared.setLanguage(previousLanguage) }
        let original = "Resource pooling lets several users share computing resources.\n\nThe application keeps the original text above the translation."
        let translated = "資源共享讓多位使用者共用運算資源。\n\nApp 會將原文保留在譯文上方。"
        let directory = ProcessInfo.processInfo.environment["PLAINTRANSLATE_PREVIEW_DIR"]
        if let directory {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
        for (language, scheme) in [(AppLanguage.en, ColorScheme.light), (.en, .dark), (.zhHK, .light), (.zhHK, .dark)] {
            L10n.shared.setLanguage(language)
            for (name, mode, size) in [
                ("compact", TranslationPresentation.compact, NSSize(width: 630, height: 520)),
                ("compact-narrow", TranslationPresentation.compact, NSSize(width: 400, height: 620)),
                ("editor", TranslationPresentation.editor, NSSize(width: 880, height: 520)),
                ("editor-narrow", TranslationPresentation.editor, NSSize(width: 620, height: 380)),
            ] {
                let model = TranslationService(presentation: mode)
                model.input = original
                model.translate()
                let request = try XCTUnwrap(model.request)
                XCTAssertEqual(request.engine, .apple)
                // Finish the fixture before mounting SwiftUI; its Translation task never runs.
                model.finish(request.id, result: .success(translated))
                XCTAssertNil(model.request)
                let view = TranslationPanelView(model: model).environment(\.colorScheme, scheme)
                try render(view, size: size, name: "\(name)-\(language.rawValue)-\(scheme)", directory: directory)
                XCTAssertEqual(model.input, original)
                XCTAssertEqual(model.output, translated)
                model.close()
            }
            let emptyModel = TranslationService()
            try render(TranslationPanelView(model: emptyModel).environment(\.colorScheme, scheme),
                       size: NSSize(width: 880, height: 520), name: "editor-empty-\(language.rawValue)-\(scheme)", directory: directory)
            emptyModel.close()
            let compactModel = TranslationService(presentation: .compact)
            try render(TranslationPanelView(model: compactModel).environment(\.colorScheme, scheme),
                       size: NSSize(width: 630, height: 230), name: "compact-empty-\(language.rawValue)-\(scheme)", directory: directory)
            compactModel.input = "Good morning."
            compactModel.translate()
            let compactRequest = try XCTUnwrap(compactModel.request)
            compactModel.finish(compactRequest.id, result: .success("早安。"))
            try render(TranslationPanelView(model: compactModel).environment(\.colorScheme, scheme),
                       size: NSSize(width: 630, height: 390), name: "compact-short-\(language.rawValue)-\(scheme)", directory: directory)
            // Seed the error state with a fresh request rather than a successful cache hit.
            compactModel.clearTranslationCache()
            compactModel.translate()
            let failedRequest = try XCTUnwrap(compactModel.request)
            compactModel.finish(failedRequest.id, result: .failure(TranslationUnsupportedPair()))
            try render(TranslationPanelView(model: compactModel).environment(\.colorScheme, scheme),
                       size: NSSize(width: 400, height: 520), name: "compact-error-\(language.rawValue)-\(scheme)", directory: directory)
            compactModel.close()
            try render(Form { ReleaseUpdateSection(model: ReleaseUpdateService(currentVersion: "0.1.3", client: GitHubReleaseClient(repository: "ChyoChan/PlainTranslate"))) }.formStyle(.grouped).environment(\.colorScheme, scheme),
                       size: NSSize(width: 680, height: 420), name: "published-updates-\(language.rawValue)-\(scheme)", directory: directory)
            let domain = "com.chyo.plaintranslate.tests.settings-render.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
            defer { defaults.removePersistentDomain(forName: domain) }
            let navigation = SettingsNavigation(defaults: defaults)
            for pane in SettingsPane.allCases {
                navigation.selectPane(pane)
                for width in [620, 840] {
                    try render(SettingsView(pane: pane, inspectCredentials: false, navigation: navigation)
                        .environment(\.colorScheme, scheme),
                        size: NSSize(width: width, height: 680),
                        name: "settings-\(pane.rawValue)-\(language.rawValue)-\(width)-\(scheme)", directory: directory)
                }
            }
        }
    }

    @MainActor
    func testCompactLongOriginalAndTranslationRemainScrollable() async throws {
        _ = NSApplication.shared
        try prepareBrandMarkForUITests()
        AppPreferences.registerDefaults()
        let model = TranslationService(presentation: .compact)
        let original = String(repeating: "An original paragraph that remains available above its translation.\n\n", count: 60)
        model.input = original
        model.translate()
        let request = try XCTUnwrap(model.request)
        model.finish(request.id, result: .success(String(repeating: "譯文仍然顯示在原文下方。\n\n", count: 20)))
        let size = NSSize(width: 630, height: 390)
        let host = NSHostingView(rootView: TranslationPanelView(model: model))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.setFrameSize(size)
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFront(nil)
        defer { window.close(); model.close() }
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try await Task.sleep(nanoseconds: 200_000_000)
        func findScrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { findScrollView(in: $0) }.first
        }
        let scroll = try XCTUnwrap(findScrollView(in: host))
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertGreaterThan(document.bounds.height, scroll.contentView.bounds.height * 2)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: document.bounds.height - scroll.contentView.bounds.height))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertGreaterThan(scroll.contentView.bounds.origin.y, scroll.contentView.bounds.height,
                             "The translation and its controls must remain reachable below a long original")
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertEqual(scroll.contentView.bounds.origin.y, 0, accuracy: 1,
                       "The original and its controls must remain reachable by scrolling up")
        XCTAssertEqual(model.input, original)
        XCTAssertFalse(model.output.isEmpty)
    }

    @MainActor
    private func render<Content: View>(_ content: Content, size: NSSize,
                                      name: String, directory: String?) throws {
        let previousAppearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: name.hasSuffix("dark") ? .darkAqua : .aqua)
        defer { NSApp.appearance = previousAppearance }
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSApp.appearance
        window.contentView = host
        host.setFrameSize(size)
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(host.bounds.size.width, size.width, accuracy: 1)
        XCTAssertEqual(host.bounds.size.height, size.height, accuracy: 1)
        if let directory {
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(png.count, 1_000)
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
        }
        window.close()
    }
}

@MainActor
func prepareBrandMarkForUITests() throws {
    guard NSImage(named: "BrandMarkTemplate") == nil else { return }
    // SwiftPM tests do not run inside the app bundle assembled by build.sh.
    let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Brand")
    let mark = try XCTUnwrap(NSImage(contentsOf: resources.appendingPathComponent("BrandMarkTemplate@2x.png")))
    mark.size = NSSize(width: 18, height: 18)
    mark.isTemplate = true
    XCTAssertTrue(mark.setName("BrandMarkTemplate"))
}
