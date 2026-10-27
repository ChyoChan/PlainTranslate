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
                ("compact", TranslationPresentation.compact, NSSize(width: 630, height: 390)),
                ("compact-narrow", TranslationPresentation.compact, NSSize(width: 400, height: 420)),
                ("editor", TranslationPresentation.editor, NSSize(width: 880, height: 520)),
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
            try render(SettingsView(inspectCredentials: false).environment(\.colorScheme, scheme),
                       size: NSSize(width: 680, height: 680), name: "settings-\(language.rawValue)-\(scheme)", directory: directory)
        }
    }

    @MainActor
    private func render<Content: View>(_ content: Content, size: NSSize,
                                      name: String, directory: String?) throws {
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
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
