// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import AppKit
import SwiftUI

/// A brief nonactivating reminder; it never opens a translation or steals focus.
enum QuickToolHUD {
    private static var panel: NSPanel?
    private static var dismiss: DispatchWorkItem?

    static func show(icon: String, message: String, dismissAfter delay: TimeInterval) {
        dismiss?.cancel()
        panel?.orderOut(nil)
        let created = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 76),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        created.isOpaque = false
        created.backgroundColor = .clear
        created.level = .floating
        created.ignoresMouseEvents = true
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        created.contentView = NSHostingView(rootView:
            Label(message, systemImage: icon)
                .font(.body).padding(16).frame(width: 420, height: 76)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)))
        if let visible = NSScreen.main?.visibleFrame {
            created.setFrameOrigin(NSPoint(x: visible.midX - 210, y: visible.maxY - 100))
        }
        panel = created
        created.orderFrontRegardless()
        let work = DispatchWorkItem {
            guard panel === created else { return }
            created.orderOut(nil)
            panel = nil
        }
        dismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
