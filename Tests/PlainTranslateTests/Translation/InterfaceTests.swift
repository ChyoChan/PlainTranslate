// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ChyoChan

import AppKit
import SwiftUI
import Translation
import Vision
import XCTest
@testable import PlainTranslate

final class InterfaceTests: XCTestCase {
    @MainActor
    func testNativeInterfacesFitAndRenderWithoutNetworkOrVisibleWindows() throws {
        _ = NSApplication.shared
        try prepareBrandMarkForUITests()
        AppPreferences.registerDefaults()
        let previousLanguage = L10n.shared.language
        let settingsModel = TranslationService.shared
        let previousEngine = settingsModel.engine
        let previousEnginePreference = UserDefaults.standard.object(forKey: DefaultsKey.translationEngine)
        defer {
            L10n.shared.setLanguage(previousLanguage)
            settingsModel.setEngine(previousEngine)
            if let previousEnginePreference { UserDefaults.standard.set(previousEnginePreference, forKey: DefaultsKey.translationEngine) }
            else { UserDefaults.standard.removeObject(forKey: DefaultsKey.translationEngine) }
        }
        settingsModel.setEngine(.apple)
        let original = "Resource pooling lets several users share computing resources.\n\nThe application keeps the original text above the translation."
        let translated = "資源共享讓多位使用者共用運算資源。\n\nApp 會將原文保留在譯文上方。"
        let directory = ProcessInfo.processInfo.environment["PLAINTRANSLATE_PREVIEW_DIR"]
        if let directory {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
        for (language, scheme) in [(AppLanguage.en, ColorScheme.light), (.en, .dark), (.zhHK, .light), (.zhHK, .dark),
                                   (.zhHans, .light), (.zhHans, .dark), (.ja, .light), (.ja, .dark)] {
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
            compactModel.finish(failedRequest.id, result: .failure(TranslationError.unsupportedLanguagePairing))
            try render(TranslationPanelView(model: compactModel).environment(\.colorScheme, scheme),
                       size: NSSize(width: 400, height: 520), name: "compact-error-\(language.rawValue)-\(scheme)", directory: directory)
            compactModel.close()
            do {
                let previousDomain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
                var fixture = previousDomain
                fixture[DefaultsKey.translationEngine] = TranslationEngine.google.rawValue
                UserDefaults.standard.setVolatileDomain(fixture, forName: UserDefaults.argumentDomain)
                defer { UserDefaults.standard.setVolatileDomain(previousDomain, forName: UserDefaults.argumentDomain) }
                for (errorName, failure) in [("retry", GoogleTranslationError.network), ("key-setup", .invalidKey)] {
                    let recoveryModel = TranslationService(presentation: .compact, googleTranslation: { _ in throw GoogleTranslationError.network })
                    recoveryModel.source = "en"
                    recoveryModel.target = "zh-Hant"
                    recoveryModel.input = original
                    recoveryModel.translate()
                    recoveryModel.finish(try XCTUnwrap(recoveryModel.request).id, result: .failure(failure))
                    recoveryModel.togglePin()
                    for (name, mode, size) in [
                        ("compact", TranslationPresentation.compact, NSSize(width: 400, height: 540)),
                        ("editor", TranslationPresentation.editor, NSSize(width: 620, height: 380)),
                    ] {
                        let model = mode == .compact ? recoveryModel : TranslationService(presentation: mode, googleTranslation: { _ in throw GoogleTranslationError.network })
                        if mode == .editor {
                            model.source = "en"
                            model.target = "zh-Hant"
                            model.input = original
                            model.translate()
                            model.finish(try XCTUnwrap(model.request).id, result: .failure(failure))
                        }
                        try render(TranslationPanelView(model: model).environment(\.colorScheme, scheme),
                                   size: size, name: "\(name)-\(errorName)-\(language.rawValue)-\(scheme)", directory: directory)
                        if mode == .editor { model.close() }
                    }
                    recoveryModel.close()
                }
            }
            try render(Form { ReleaseUpdateSection(model: ReleaseUpdateService(currentVersion: "0.1.3", client: GitHubReleaseClient(repository: "ChyoChan/PlainTranslate"))) }.formStyle(.grouped).environment(\.colorScheme, scheme),
                       size: NSSize(width: 680, height: 420), name: "published-updates-\(language.rawValue)-\(scheme)", directory: directory)
            for granted in [false, true] {
                var settingsOpened = false
                try render(Form {
                    Section {
                        AccessibilityPermissionView(granted: granted, language: language,
                                                    openSettings: { settingsOpened = true })
                    }
                }.formStyle(.grouped).environment(\.colorScheme, scheme),
                    size: NSSize(width: 620, height: 230),
                    name: "accessibility-\(granted ? "granted" : "not-granted")-\(language.rawValue)-\(scheme)", directory: directory)
                XCTAssertFalse(settingsOpened, "Rendering status must not open settings or request access")
            }
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
                try render(SettingsView(pane: pane, inspectCredentials: false, navigation: navigation)
                    .font(.system(size: 20)).environment(\.colorScheme, scheme),
                    size: NSSize(width: 620, height: 680),
                    name: "settings-\(pane.rawValue)-\(language.rawValue)-accessible-\(scheme)", directory: directory)
            }
            navigation.selectPane(.translation)
            settingsModel.setEngine(.google)
            for width in [620, 840] {
                try render(SettingsView(pane: .translation, inspectCredentials: false, navigation: navigation)
                    .environment(\.colorScheme, scheme),
                    size: NSSize(width: width, height: 680),
                    name: "settings-google-\(language.rawValue)-\(width)-\(scheme)", directory: directory)
            }
            XCTAssertNil(settingsModel.request, "Rendering engine settings must never submit text")
            XCTAssertFalse(settingsModel.busy)
            settingsModel.setEngine(.apple)
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
    func testCancelledTranslationShowsRestartInBothPresentations() async throws {
        _ = NSApplication.shared
        try prepareBrandMarkForUITests()
        let defaults = UserDefaults.standard
        let previous = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        let previousLanguage = L10n.shared.language
        var fixture = previous
        fixture[DefaultsKey.translationEngine] = TranslationEngine.google.rawValue
        defaults.setVolatileDomain(fixture, forName: UserDefaults.argumentDomain)
        L10n.shared.setLanguage(.en)
        defer {
            defaults.setVolatileDomain(previous, forName: UserDefaults.argumentDomain)
            L10n.shared.setLanguage(previousLanguage)
        }
        for mode in [TranslationPresentation.compact, .editor] {
            var submissions: [TranslationRequest] = []
            let model = TranslationService(presentation: mode, googleTranslation: { request in
                submissions.append(request)
                return "Fixture translation."
            })
            model.input = "Resume this text without editing."
            model.translate()
            let cancelled = try XCTUnwrap(model.request)
            model.cancel()
            XCTAssertNil(model.request)
            let size = NSSize(width: 880, height: 620)
            let host = NSHostingView(rootView: TranslationPanelView(model: model))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.setFrameSize(size)
            defer { window.close(); model.close() }
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 100_000_000)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let recognition = VNRecognizeTextRequest()
            recognition.recognitionLanguages = ["en-US"]
            recognition.recognitionLevel = .accurate
            recognition.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage), options: [:]).perform([recognition])
            let labels = (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            XCTAssertTrue(labels.contains("Translate"), "Cancelled \(mode) must offer Translate without editing; found \(labels)")
            if let directory = ProcessInfo.processInfo.environment["PLAINTRANSLATE_PREVIEW_DIR"] {
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("cancelled-\(mode).png"))
            }
            XCTAssertTrue(submissions.isEmpty, "Cancelling must not restart automatically")
            model.translate()
            let deadline = Date().addingTimeInterval(2)
            while model.output.isEmpty, Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
            XCTAssertEqual(submissions.count, 1)
            XCTAssertEqual(submissions.first?.text, cancelled.text)
            XCTAssertEqual(submissions.first?.engine, .google)
            XCTAssertEqual(model.output, "Fixture translation.")
            model.finish(cancelled.id, result: .success("Stale result"))
            XCTAssertEqual(model.output, "Fixture translation.")
        }
    }

    @MainActor
    private func render<Content: View>(_ content: Content, size: NSSize,
                                      name: String, directory: String?) throws {
        let previousAppearance = NSApp.appearance
        let appearance: NSAppearance.Name = name.contains("-accessible-")
            ? (name.hasSuffix("dark") ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
            : (name.hasSuffix("dark") ? .darkAqua : .aqua)
        NSApp.appearance = NSAppearance(named: appearance)
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
