// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import AppKit
import SwiftUI
import XCTest
@testable import PlainTranslate

final class LanguageSelectionTests: XCTestCase {
    @MainActor
    func testEngineHighlightSlidesAndIgnoresRepeatedOrDisabledClicks() throws {
        _ = NSApplication.shared
        let state = EngineSelectionState()
        let (host, window) = fixture(EngineSelectionFixture(state: state).accentColor(.blue),
                                    size: NSSize(width: 190, height: 28))
        defer { window.close() }
        settle(0.1)
        func sample() throws -> CGFloat {
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            return try blueCenter(bitmap, row: Int(24 * scale), columns: 0..<bitmap.pixelsWide) / scale
        }
        func assertSlide(from start: CGFloat, to end: CGFloat) throws {
            let points = try animationFrames(sample)
            settle(0.1)
            XCTAssertEqual(try sample(), end, accuracy: 3)
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                XCTAssertTrue(points.contains { $0 > min(start, end) + 3 && $0 < max(start, end) - 3 },
                              "The engine highlight must slide as one shape: \(points)")
            }
        }
        let apple = try sample()
        let google = apple + 95
        try click(host, window: window, point: NSPoint(x: 142, y: 14))
        XCTAssertEqual(state.engine, .google)
        XCTAssertEqual(state.changes, 1)
        try assertSlide(from: apple, to: google)
        try click(host, window: window, point: NSPoint(x: 142, y: 14))
        XCTAssertEqual(state.changes, 1, "Clicking the active engine must not submit another request")
        try click(host, window: window, point: NSPoint(x: 47, y: 14))
        XCTAssertEqual(state.engine, .apple)
        try assertSlide(from: google, to: apple)
        for x in [142.0, 47.0, 142.0] {
            try click(host, window: window, point: NSPoint(x: x, y: 14))
            settle(0.03)
        }
        settle(0.3)
        XCTAssertEqual(state.engine, .google)
        XCTAssertEqual(state.changes, 5)
        XCTAssertEqual(try sample(), google, accuracy: 3)
        state.enabled = false
        settle(0.05)
        try click(host, window: window, point: NSPoint(x: 47, y: 14))
        XCTAssertEqual(state.engine, .google)
        XCTAssertEqual(state.changes, 5)
    }

    @MainActor
    func testAnimationSamplingSeesIntermediatePositions() throws {
        _ = NSApplication.shared
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let position = AnimationPosition()
        let (host, window) = fixture(AnimationControl(position: position), size: NSSize(width: 400, height: 60))
        defer { window.close() }
        settle(0.1)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        func sample() throws -> CGFloat {
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            return try blueCenter(bitmap, row: Int(30 * scale), columns: 0..<bitmap.pixelsWide) / scale
        }
        let start = try sample()
        position.moved = true
        let points = try animationFrames(sample)
        settle(0.2)
        let end = try sample()
        XCTAssertGreaterThan(end - start, 150)
        XCTAssertTrue(points.contains { $0 > start + 5 && $0 < end - 5 },
                      "The capture loop must see a known animation in progress: \(points)")
    }

    @MainActor
    func testNativeLanguageTabsSlideForwardAndBackwardAcrossPresentations() throws {
        _ = NSApplication.shared
        try prepareBrandMarkForUITests()
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let previousLanguage = L10n.shared.language
        let keys = [DefaultsKey.appLanguage, DefaultsKey.translationRecentSourceLanguages,
                    DefaultsKey.translationRecentTargetLanguages, DefaultsKey.translationSourceTabs,
                    DefaultsKey.translationTargetTabs]
        let previousValues = keys.map { UserDefaults.standard.object(forKey: $0) }
        L10n.shared.setLanguage(.en)
        for key in keys.dropFirst() { UserDefaults.standard.set(["zh-Hant", "en", "ja"], forKey: key) }
        defer {
            L10n.shared.setLanguage(previousLanguage)
            for (key, value) in zip(keys, previousValues) {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        for (mode, source) in [(TranslationPresentation.editor, true), (.editor, false), (.compact, false)] {
            let model = TranslationService(presentation: mode)
            model.source = "en"
            model.target = "en"
            let size = mode == .editor ? NSSize(width: 880, height: 520) : NSSize(width: 630, height: 390)
            let view = TranslationPanelView(model: model).environment(\.colorScheme, .dark).accentColor(.blue)
            let (host, window) = fixture(view, size: size)
            defer { window.close(); model.close() }
            settle(0.1)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            // The language-row underline is below the header in each presentation.
            let row = Int((mode == .editor ? 104 : 93) * scale)
            let columns = mode == .compact ? 0..<bitmap.pixelsWide :
                (source ? 0..<(bitmap.pixelsWide / 2) : (bitmap.pixelsWide / 2)..<bitmap.pixelsWide)
            func sample() throws -> CGFloat {
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                return try blueCenter(bitmap, row: row, columns: columns) / scale
            }
            let english = try sample()
            if source { model.setSource("zh-Hant") } else { model.setTarget("zh-Hant") }
            settle(0.3)
            let chinese = try sample()
            XCTAssertGreaterThan(abs(english - chinese), 30)
            let clickY = CGFloat(row) / scale - 18

            func select(_ x: CGFloat) throws {
                try click(host, window: window, point: NSPoint(x: x, y: clickY))
            }
            func assertSlide(from start: CGFloat, to end: CGFloat) throws {
                let points = try animationFrames(sample)
                settle(0.1)
                XCTAssertEqual(try sample(), end, accuracy: 4)
                XCTAssertTrue(points.contains { $0 > min(start, end) + 3 && $0 < max(start, end) - 3 },
                              "\(mode), source=\(source) must slide through intermediate positions: \(points)")
            }
            try select(english)
            XCTAssertEqual(source ? model.source : model.target, "en")
            try assertSlide(from: chinese, to: english)
            try select(chinese)
            XCTAssertEqual(source ? model.source : model.target, "zh-Hant")
            try assertSlide(from: english, to: chinese)
            for x in [english, chinese, english] { try select(x); settle(0.03) }
            settle(0.3)
            XCTAssertEqual(source ? model.source : model.target, "en")
            XCTAssertEqual(try sample(), english, accuracy: 4, "Rapid clicks must finish at the selected language")
        }
    }

    @MainActor
    private func fixture<Content: View>(_ content: Content, size: NSSize) -> (NSView, NSWindow) {
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.setFrameSize(size)
        // Window visibility enables native input and display ticks; this stays transparent and offscreen.
        window.alphaValue = 0
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFront(nil)
        return (host, window)
    }

    @MainActor
    private func click(_ host: NSView, window: NSWindow, point: NSPoint) throws {
        XCTAssertEqual(window.alphaValue, 0)
        let location = host.convert(point, to: nil)
        let timestamp = ProcessInfo.processInfo.systemUptime
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: location,
            modifierFlags: [], timestamp: timestamp, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: location,
            modifierFlags: [], timestamp: timestamp + 0.01, windowNumber: window.windowNumber,
            context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
        NSApp.postEvent(up, atStart: false)
        window.sendEvent(down)
        window.sendEvent(up)
    }

    private func blueCenter(_ bitmap: NSBitmapImageRep, row: Int, columns: Range<Int>) throws -> CGFloat {
        var pixels: [Int] = []
        for x in columns {
            guard let color = bitmap.colorAt(x: x, y: row)?.usingColorSpace(.deviceRGB),
                  color.blueComponent > 0.6, color.blueComponent > color.redComponent * 1.5,
                  color.blueComponent > color.greenComponent * 1.1 else { continue }
            pixels.append(x)
        }
        XCTAssertFalse(pixels.isEmpty, "The selected underline must be visible")
        XCTAssertFalse(zip(pixels, pixels.dropFirst()).contains { $1 - $0 > 2 },
                       "The underline must move as one line, not crossfade between distant lines")
        return CGFloat(pixels.reduce(0, +)) / CGFloat(max(1, pixels.count))
    }

    @MainActor
    private func animationFrames(_ sample: () throws -> CGFloat) rethrows -> [CGFloat] {
        try (0..<12).map { _ in settle(0.015); return try sample() }
    }

    private func settle(_ interval: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(interval))
    }
}

private final class EngineSelectionState: ObservableObject {
    @Published var engine = TranslationEngine.apple
    @Published var enabled = true
    var changes = 0
}

private struct EngineSelectionFixture: View {
    @ObservedObject var state: EngineSelectionState
    var body: some View {
        TranslationEngineControl(selection: Binding(get: { state.engine }, set: {
            state.engine = $0
            state.changes += 1
        }), label: "Engine", appleHelp: "Local", googleHelp: "Cloud")
        .disabled(!state.enabled)
    }
}

private final class AnimationPosition: ObservableObject {
    @Published var moved = false
}

private struct AnimationControl: View {
    @ObservedObject var position: AnimationPosition
    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Color.blue).frame(width: 20, height: 4)
                .offset(x: position.moved ? 200 : 0)
                .animation(.linear(duration: 0.4), value: position.moved)
            Spacer(minLength: 0)
        }.frame(width: 400, height: 60)
    }
}
