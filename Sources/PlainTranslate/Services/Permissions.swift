// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import AppKit
import ApplicationServices
import Combine

/// Permission is requested only from the explicit Settings button.
final class Permissions: ObservableObject {
    static let shared = Permissions()
    @Published private(set) var accessibility = AXIsProcessTrusted()
    private var activation: AnyCancellable?

    private init() {
        activation = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != accessibility { accessibility = trusted }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        refresh()
    }
}
