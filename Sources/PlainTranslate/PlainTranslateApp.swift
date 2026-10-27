// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ChyoChan

import AppKit
import SwiftUI

@main
struct PlainTranslateApp: App {
    @NSApplicationDelegateAdaptor(PlainTranslateDelegate.self) private var delegate
    @ObservedObject private var l10n = L10n.shared

    init() {
        AppPreferences.registerDefaults()
    }

    var body: some Scene {
        MenuBarExtra {
            Button(label("Open translator…", "開啟翻譯…")) {
                TranslationService.shared.open()
            }
            Button(label("Translate copied text", "翻譯已複製文字")) {
                TranslationService.shared.useCopiedText(presentation: .compact)
            }
            Divider()
            Button(label("Settings…", "設定…")) { SettingsNavigation.shared.show() }
                .keyboardShortcut(",", modifiers: .command)
            Divider()
            Button(label("Quit PlainTranslate", "結束 PlainTranslate")) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image("BrandMarkTemplate")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .accessibilityLabel("PlainTranslate")
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(label("Settings…", "設定…")) { SettingsNavigation.shared.show() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    private func label(_ english: String, _ chinese: String) -> String {
        l10n.language == .en ? english : chinese
    }
}

final class PlainTranslateDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Permissions.shared.refresh()
        TranslationService.shared.start()
        TranslationService.shared.open()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        TranslationService.shared.open()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        TranslationService.shared.stop()
    }
}
