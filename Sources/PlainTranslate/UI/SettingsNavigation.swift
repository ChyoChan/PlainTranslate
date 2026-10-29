// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ChyoChan

import AppKit
import Combine
import SwiftUI

/// The translator is hosted by AppKit, so it cannot rely on a Settings scene environment.
final class SettingsNavigation: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = SettingsNavigation()
    @Published var focusGoogleCredentials = false
    private var window: NSWindow?

    func requestGoogleCredentials() {
        precondition(Thread.isMainThread)
        TranslationService.shared.setEngine(.google)
        focusGoogleCredentials = true
        show()
    }

    func show() {
        precondition(Thread.isMainThread)
        TranslationService.shared.hideForSettings()
        if window == nil {
            let created = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 680),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                   backing: .buffered, defer: false)
            created.isReleasedWhenClosed = false
            created.contentMinSize = NSSize(width: 620, height: 560)
            created.contentView = NSHostingView(rootView: SettingsView())
            created.delegate = self
            created.center()
            window = created
        }
        window?.title = L10n.shared.isChinese ? "PlainTranslate 設定" : "PlainTranslate Settings"
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func returnToTranslation() {
        precondition(Thread.isMainThread)
        window?.close()
        TranslationService.shared.open(TranslationService.shared.presentation)
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        focusGoogleCredentials = false
        window?.contentView = nil
        window = nil
    }
}
