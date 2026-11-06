// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Presentation is independent of the request: expanding must not restart a
/// translation or discard the copied original.
enum TranslationPresentation: Equatable {
    case compact, editor

    var preferredSize: CGSize {
        switch self {
        case .compact: return CGSize(width: TranslationCompactLayout.defaultWidth, height: 230)
        case .editor: return CGSize(width: 880, height: 520)
        }
    }

    var minimumSize: CGSize {
        switch self {
        case .compact: return CGSize(width: 400, height: 210)
        case .editor: return CGSize(width: 620, height: 380)
        }
    }
}

enum TranslationCompactLayout {
    static let defaultWidth = 630.0
    static let defaultFontSize = 20.0
    static let widthRange = 400.0...1_200.0
    static let fontSizeRange = 12.0...32.0

    static func width(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return defaultWidth }
        return min(max(value, widthRange.lowerBound), widthRange.upperBound)
    }

    static func fontSize(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return defaultFontSize }
        return min(max(value, fontSizeRange.lowerBound), fontSizeRange.upperBound)
    }

    static func height(for measuredHeight: CGFloat, available: CGFloat) -> CGFloat {
        min(max(TranslationPresentation.compact.minimumSize.height, ceil(measuredHeight)),
            min(720, max(0, available)))
    }
}

enum TranslationDismissalPolicy {
    static func shouldDismiss(presentation: TranslationPresentation, isVisible: Bool, isPinned: Bool = false,
                              clickIsInside: Bool, menuIsTracking: Bool,
                              hasModal: Bool, isAssistiveKeyboard: Bool) -> Bool {
        presentation == .compact && isVisible && !isPinned && !clickIsInside &&
            !menuIsTracking && !hasModal && !isAssistiveKeyboard
    }
}

enum TranslationWindowPolicy {
    // Keep one activating host across modes so editor selection can activate the app without restarting translation.
    static func makePanel(contentRect: NSRect) -> TranslationPanel {
        TranslationPanel(contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
    }

    static func configure(_ panel: NSPanel, for presentation: TranslationPresentation) {
        let compact = presentation == .compact
        panel.isFloatingPanel = compact
        panel.level = compact ? .floating : .normal
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = compact
            ? [.moveToActiveSpace, .fullScreenAuxiliary, .transient] : [.managed]
    }

    static func present(_ panel: NSPanel, for presentation: TranslationPresentation) {
        if presentation == .compact {
            if panel.isMainWindow { panel.resignMain() }
            // Show the result without taking keyboard focus from the app that supplied the text.
            panel.orderFrontRegardless()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.makeMain()
        }
    }
}

final class TranslationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { !isFloatingPanel }
    override func cancelOperation(_ sender: Any?) { close() }
}
